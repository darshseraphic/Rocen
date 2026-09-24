import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'github_backup_service.dart';
import 'master_key_local_store.dart';
import 'master_key_manager.dart';
import 'password_key_derivation.dart';
import 'password_state_manager.dart';
import 'secure_bytes.dart';

/// Production integration for Block B.
///
/// This service is the only orchestration layer that establishes/recoveries
/// the dataset Master Key before Stage 5 exists. It never derives a Master Key
/// from a password and never creates a replacement key during recovery.
class MasterKeyProductionService {
  MasterKeyProductionService._();

  static final MasterKeyProductionService instance =
      MasterKeyProductionService._();

  /// One in-process serialization gate for every local dataset-MK authority
  /// mutation. Durable record revisions provide the corresponding stale-writer
  /// rejection when a caller writes from an old read.
  Future<void> _authorityMutationTail = Future<void>.value();

  Future<MasterKeyLocalRecord?> readLocalRecord() =>
      MasterKeyLocalStore.read();

  Future<void> establishFirstDevice({
    required String password,
    required List<String> mnemonicWords,
    GithubBackupService? remoteService,
    String? repository,
  }) {
    return _runAuthorityMutation<void>(
      () => MasterKeyManager.instance.runExclusiveInitialization<void>(
        (lease) => _establishFirstDevice(
          password: password,
          mnemonicWords: mnemonicWords,
          remoteService: remoteService,
          repository: repository,
          initializationLease: lease,
        ),
      ),
    );
  }

  Future<void> _establishFirstDevice({
    required String password,
    required List<String> mnemonicWords,
    GithubBackupService? remoteService,
    String? repository,
    required MasterKeyInitializationLease initializationLease,
  }) async {
    final MasterKeyManager manager = MasterKeyManager.instance;
    if (remoteService != null &&
        (repository == null || repository.trim().isEmpty)) {
      throw StateError(
        'repository is required when remote Master Key recovery publication is requested',
      );
    }
    if (manager.state == MasterKeyState.authoritative) {
      return;
    }

    final MasterKeyLocalRecord? existingLocal = await MasterKeyLocalStore.read();
    if (existingLocal != null) {
      await _restoreFromLocal(existingLocal, password, mnemonicWords, initializationLease: initializationLease);
      if (remoteService != null) {
        await _associateRemote(
          service: remoteService,
          password: password,
          mnemonicWords: mnemonicWords,
          repository: repository,
        );
      }
      return;
    }

    // Existing remote authority must be discovered before generation.
    if (remoteService != null) {
      final observedDeviceKey =
          await remoteService.fetchNoteFileWithRefSha('device_key.json');
      final Map<String, dynamic>? remote = observedDeviceKey.content;
      final Map<String, dynamic>? remotePasswordState =
          await remoteService.fetchNoteFile('password_state.json');
      if (remote == null && remotePasswordState != null) {
        throw StateError(
          'existing remote dataset was found without the supported recovery wrapper',
        );
      }
      if (remote == null && observedDeviceKey.refSha != null) {
        throw StateError(
          'selected repository is already initialized but has no supported Rocen authority record; reset the disposable development repository before first-device setup',
        );
      }
      if (remote != null) {
        final String recoveryWrap = jsonEncode(remote);
        await _recoverFromRemote(
          service: remoteService,
          password: password,
          mnemonicWords: mnemonicWords,
          repository: repository,
          knownRecoveryWrapJson: recoveryWrap,
          initializationLease: initializationLease,
        );
        return;
      }
    }

    manager.generateProvisionalMasterKey();
    Uint8List provisional = Uint8List(0);
    Uint8List? passwordKey;
    Uint8List? recoveryKey;
    try {
      provisional = manager.requireProvisionalMasterKeyBytes();
      final String passwordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
        masterKeyBytes: provisional,
        rawPassword: password,
      );
      final String recoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
        masterKeyBytes: provisional,
        rawPassword: password,
        mnemonicWords: mnemonicWords,
      );
      final String verifier =
          await PasswordKeyDerivation.createPasswordVerifier(password);

      passwordKey = await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
        wrapJson: passwordWrap,
        rawPassword: password,
      );
      recoveryKey = await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
        wrapJson: recoveryWrap,
        rawPassword: password,
        mnemonicWords: mnemonicWords,
      );
      if (passwordKey == null ||
          recoveryKey == null ||
          !_constantTimeEquals(provisional, passwordKey) ||
          !_constantTimeEquals(provisional, recoveryKey)) {
        throw StateError('new Master Key wrapper validation failed');
      }

      final MasterKeyLocalRecord local = MasterKeyLocalRecord.authoritative(
        passwordVerifier: verifier,
        passwordWrap: passwordWrap,
        recoveryWrap: recoveryWrap,
        remoteRecoveryStatus: RemoteRecoveryStatus.unpublished,
        repository: repository,
      );
      await MasterKeyLocalStore.write(local);
      final MasterKeyLocalRecord? readBack = await MasterKeyLocalStore.read();
      if (readBack == null ||
          readBack.passwordWrap != passwordWrap ||
          readBack.recoveryWrap != recoveryWrap ||
          readBack.passwordVerifier != verifier) {
        throw StateError('local Master Key security record verification failed');
      }

      if (remoteService != null) {
        if (repository == null || repository.trim().isEmpty) {
          throw StateError(
            'repository is required when publishing a remote Master Key recovery wrapper',
          );
        }
        try {
          await remoteService.createFileIfAbsent(
            path: 'device_key.json',
            content: recoveryWrap,
            message: 'rocen: initialize master key recovery',
          );

          final Map<String, dynamic>? remoteRead =
              await remoteService.fetchNoteFile('device_key.json');
          if (remoteRead == null ||
              !await _remoteRecoveryMatches(
                remoteRead,
                password,
                mnemonicWords,
                provisional,
              )) {
            await MasterKeyLocalStore.write(
              local.copyWith(
                remoteRecoveryStatus: RemoteRecoveryStatus.conflict,
                repository: repository,
              ),
            );
            throw StateError('remote recovery wrapper did not match local Master Key');
          }

          await MasterKeyLocalStore.write(
            local.copyWith(
              remoteRecoveryStatus: RemoteRecoveryStatus.published,
              repository: repository,
              clearPreviousPublishedRecoveryWrap: true,
            ),
          );
          await PasswordStateManager.initializeOrJoinState(
            service: remoteService,
            allowCreateInitialState: true,
          );
          manager.promoteProvisionalToAuthoritative();
          return;
        } on GithubFileAlreadyExists {
          // Remote creation lost the initialization race. Never overwrite it.
          manager.discardProvisionalMasterKey();
          final Map<String, dynamic>? remoteRead =
              await remoteService.fetchNoteFile('device_key.json');
          if (remoteRead == null) {
            throw StateError('device_key.json race winner could not be read');
          }
          await _recoverFromRemote(
            service: remoteService,
            password: password,
            mnemonicWords: mnemonicWords,
            repository: repository,
            knownRecoveryWrapJson: jsonEncode(remoteRead),
            initializationLease: initializationLease,
          );
          return;
        } catch (_) {
          manager.discardProvisionalMasterKey();
          rethrow;
        }
      }

      manager.promoteProvisionalToAuthoritative();
    } catch (_) {
      if (manager.state == MasterKeyState.provisional) {
        manager.discardProvisionalMasterKey();
      }
      rethrow;
    } finally {
      zeroBytes(provisional);
      if (passwordKey != null) zeroBytes(passwordKey);
      if (recoveryKey != null) zeroBytes(recoveryKey);
    }
  }

  Future<void> _restoreFromLocal(
    MasterKeyLocalRecord record,
    String password,
    List<String> mnemonicWords, {
    required MasterKeyInitializationLease initializationLease,
  }) async {
    record.validate();
    final bool valid = await PasswordKeyDerivation.verifyPassword(
      password,
      record.passwordVerifier,
    );
    if (!valid) {
      throw StateError('password verification failed');
    }

    final Uint8List? passwordKey =
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
      wrapJson: record.passwordWrap,
      rawPassword: password,
    );
    if (passwordKey == null ||
        passwordKey.length != MasterKeyManager.masterKeyLengthBytes) {
      if (passwordKey != null) zeroBytes(passwordKey);
      throw StateError('local Password-KEK wrapper is invalid');
    }

    final Uint8List? recoveryKey =
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
      wrapJson: record.recoveryWrap,
      rawPassword: password,
      mnemonicWords: mnemonicWords,
    );
    if (recoveryKey == null ||
        recoveryKey.length != MasterKeyManager.masterKeyLengthBytes) {
      zeroBytes(passwordKey);
      if (recoveryKey != null) zeroBytes(recoveryKey);
      throw StateError(
        'local Recovery-KEK wrapper is invalid; refusing to trust local authority',
      );
    }

    if (!_constantTimeEquals(passwordKey, recoveryKey)) {
      zeroBytes(passwordKey);
      zeroBytes(recoveryKey);
      throw StateError(
        'local Password-KEK and Recovery-KEK wrappers resolve to different Master Keys',
      );
    }

    // Only after both wrappers resolve to the exact same MK is the candidate
    // transferred to the sole authoritative MasterKeyManager owner.
    try {
      MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(
        passwordKey,
        lease: initializationLease,
      );
    } finally {
      // MasterKeyManager consumes/zeros passwordKey.
      zeroBytes(recoveryKey);
    }
  }

  Future<void> recoverFromRemote({
    required GithubBackupService service,
    required String password,
    required List<String> mnemonicWords,
    String? repository,
    String? knownRecoveryWrapJson,
  }) {
    return _runAuthorityMutation<void>(
      () => MasterKeyManager.instance.runExclusiveInitialization<void>(
        (lease) => _recoverFromRemote(
          service: service,
          password: password,
          mnemonicWords: mnemonicWords,
          repository: repository,
          knownRecoveryWrapJson: knownRecoveryWrapJson,
          initializationLease: lease,
        ),
      ),
    );
  }

  Future<void> _recoverFromRemote({
    required GithubBackupService service,
    required String password,
    required List<String> mnemonicWords,
    String? repository,
    String? knownRecoveryWrapJson,
    required MasterKeyInitializationLease initializationLease,
  }) async {
    if (repository == null || repository.trim().isEmpty) {
      throw StateError(
        'repository is required when recovering a remote Master Key authority',
      );
    }
    final Map<String, dynamic>? remote =
        knownRecoveryWrapJson == null
            ? await service.fetchNoteFile('device_key.json')
            : (jsonDecode(knownRecoveryWrapJson) as Map<String, dynamic>);
    if (remote == null) {
      throw StateError('existing device_key.json was not found');
    }

    final String recoveryWrap = jsonEncode(remote);
    final Uint8List? recovered =
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
      wrapJson: recoveryWrap,
      rawPassword: password,
      mnemonicWords: mnemonicWords,
    );
    if (recovered == null || recovered.length != 32) {
      if (recovered != null) zeroBytes(recovered);
      throw StateError('recovery authentication failed');
    }

    try {
      final MasterKeyLocalRecord? local = await MasterKeyLocalStore.read();
      if (local != null) {
        if (local.remoteRecoveryStatus == RemoteRecoveryStatus.conflict) {
          throw StateError(
            'local Master Key authority is already in remote recovery conflict; refusing to clear or replace the conflict',
          );
        }
        final Uint8List localKey = await _validateLocalAuthorityRecord(
          local,
          password,
          mnemonicWords,
        );
        try {
          if (!_constantTimeEquals(recovered, localKey)) {
            await MasterKeyLocalStore.write(
              local.copyWith(
                remoteRecoveryStatus: RemoteRecoveryStatus.conflict,
                repository: repository,
              ),
            );
            throw StateError(
              'local and remote Master Key authorities conflict',
            );
          }
        } finally {
          zeroBytes(localKey);
        }

        if (MasterKeyManager.instance.state == MasterKeyState.authoritative) {
          throw StateError('Master Key is already authoritative');
        }
        final Uint8List candidate = Uint8List.fromList(recovered);
        try {
          MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(
            candidate,
            lease: initializationLease,
          );
        } catch (_) {
          zeroBytes(candidate);
          rethrow;
        }
        await MasterKeyLocalStore.write(
          local.copyWith(
            remoteRecoveryStatus: RemoteRecoveryStatus.published,
            repository: repository,
            clearPreviousPublishedRecoveryWrap: true,
          ),
        );
        await PasswordStateManager.initializeOrJoinState(
          service: service,
          allowCreateInitialState: true,
        );
        return;
      }

      if (MasterKeyManager.instance.state == MasterKeyState.authoritative) {
        throw StateError('Master Key is already authoritative');
      }

      final String localVerifier =
          await PasswordKeyDerivation.createPasswordVerifier(password);
      final String passwordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
        masterKeyBytes: recovered,
        rawPassword: password,
      );
      final Uint8List? passwordWrapCheck =
          await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
        wrapJson: passwordWrap,
        rawPassword: password,
      );
      if (passwordWrapCheck == null ||
          !_constantTimeEquals(recovered, passwordWrapCheck)) {
        if (passwordWrapCheck != null) zeroBytes(passwordWrapCheck);
        throw StateError(
          'local Password-KEK wrapper validation failed during remote recovery',
        );
      }
      zeroBytes(passwordWrapCheck);

      final MasterKeyLocalRecord record = MasterKeyLocalRecord.authoritative(
        passwordVerifier: localVerifier,
        passwordWrap: passwordWrap,
        recoveryWrap: recoveryWrap,
        remoteRecoveryStatus: RemoteRecoveryStatus.published,
        repository: repository,
      );
      await MasterKeyLocalStore.write(record);
      final MasterKeyLocalRecord? readBack = await MasterKeyLocalStore.read();
      if (readBack == null ||
          readBack.recoveryWrap != recoveryWrap ||
          readBack.passwordWrap != passwordWrap ||
          readBack.passwordVerifier != localVerifier) {
        throw StateError('local recovery record verification failed');
      }
      final Uint8List candidate = Uint8List.fromList(recovered);
      try {
        MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(
          candidate,
          lease: initializationLease,
        );
      } catch (_) {
        zeroBytes(candidate);
        rethrow;
      }

      await PasswordStateManager.initializeOrJoinState(
        service: service,
        allowCreateInitialState: true,
      );
    } catch (_) {
      // The manager consumes the recovered buffer only on successful install.
      zeroBytes(recovered);
      rethrow;
    }
  }

  Future<void> associateRemote({
    required GithubBackupService service,
    required String password,
    required List<String> mnemonicWords,
    String? repository,
  }) {
    return _runAuthorityMutation<void>(() async {
      final MasterKeyManager manager = MasterKeyManager.instance;
      if (manager.state == MasterKeyState.none) {
        await manager.runExclusiveInitialization<void>(
          (lease) => _associateRemote(
            service: service,
            password: password,
            mnemonicWords: mnemonicWords,
            repository: repository,
            initializationLease: lease,
          ),
        );
        return;
      }
      await _associateRemote(
        service: service,
        password: password,
        mnemonicWords: mnemonicWords,
        repository: repository,
      );
    });
  }

  Future<void> _associateRemote({
    required GithubBackupService service,
    required String password,
    required List<String> mnemonicWords,
    String? repository,
    MasterKeyInitializationLease? initializationLease,
  }) async {
    if (repository == null || repository.trim().isEmpty) {
      throw StateError(
        'repository is required when associating remote Master Key recovery',
      );
    }
    final MasterKeyLocalRecord? local = await MasterKeyLocalStore.read();
    if (local == null) {
      throw StateError('local Master Key authority is not established');
    }
    if (local.remoteRecoveryStatus == RemoteRecoveryStatus.conflict) {
      throw StateError(
        'local Master Key authority is in remote recovery conflict; refusing to replace or overwrite either authority',
      );
    }
    final Uint8List localKey = await _validateLocalAuthorityRecord(
      local,
      password,
      mnemonicWords,
    );
    try {
      final MasterKeyManager manager = MasterKeyManager.instance;
      if (manager.state == MasterKeyState.none) {
        if (initializationLease == null) {
          throw StateError(
            'local Master Key restoration requires the active initialization lease',
          );
        }
        final Uint8List candidate = Uint8List.fromList(localKey);
        manager.setAuthoritativeMasterKeyFromRecovery(
          candidate,
          lease: initializationLease,
        );
      }

      final observedDeviceKey =
          await service.fetchNoteFileWithRefSha('device_key.json');
      final Map<String, dynamic>? remote = observedDeviceKey.content;
      if (remote == null) {
        if (observedDeviceKey.refSha != null) {
          throw StateError(
            'selected repository is already initialized but has no supported Rocen authority record; reset the disposable development repository before publishing recovery metadata',
          );
        }
        await service.createFileIfAbsent(
          path: 'device_key.json',
          content: local.recoveryWrap,
          message: 'rocen: publish master key recovery',
        );
        final Map<String, dynamic>? published =
            await service.fetchNoteFile('device_key.json');
        if (published == null || jsonEncode(published) != local.recoveryWrap) {
          throw StateError(
            'remote recovery wrapper read-back did not match local authority',
          );
        }
        await MasterKeyLocalStore.write(
          local.copyWith(
            remoteRecoveryStatus: RemoteRecoveryStatus.published,
            repository: repository,
            clearPreviousPublishedRecoveryWrap: true,
          ),
        );
        await PasswordStateManager.initializeOrJoinState(
          service: service,
          allowCreateInitialState: true,
        );
        return;
      }

      final String remoteWrap = jsonEncode(remote);
      if (remoteWrap == local.recoveryWrap) {
        await MasterKeyLocalStore.write(
          local.copyWith(
            remoteRecoveryStatus: RemoteRecoveryStatus.published,
            repository: repository,
            clearPreviousPublishedRecoveryWrap: true,
          ),
        );
        await PasswordStateManager.initializeOrJoinState(
          service: service,
          allowCreateInitialState: true,
        );
        return;
      }

      if (local.remoteRecoveryStatus == RemoteRecoveryStatus.unpublished &&
          local.previousPublishedRecoveryWrap != null) {
        if (remoteWrap != local.previousPublishedRecoveryWrap) {
          // After a remote commit succeeds, a crash may occur before the local
          // completion marker is written. On restart, the remote wrapper can
          // therefore already be the new wrapper. Prove that it resolves to the
          // same local MK before treating the remote state as committed.
          final bool remoteAlreadyCommitted = await _remoteWrapMatchesKey(
            remoteWrap,
            password,
            mnemonicWords,
            localKey,
          );
          if (!remoteAlreadyCommitted) {
            await MasterKeyLocalStore.write(
              local.copyWith(
                remoteRecoveryStatus: RemoteRecoveryStatus.conflict,
                repository: repository,
              ),
            );
            throw StateError(
              'remote recovery metadata conflicts with the pending local password rotation',
            );
          }
          await MasterKeyLocalStore.write(
            local.copyWith(
              remoteRecoveryStatus: RemoteRecoveryStatus.published,
              repository: repository,
              clearPreviousPublishedRecoveryWrap: true,
            ),
          );
          await PasswordStateManager.initializeOrJoinState(
            service: service,
            allowCreateInitialState: true,
          );
          return;
        }
        await PasswordStateManager.publishRotationAtomically(
          service: service,
          recoveryWrap: local.recoveryWrap,
          expectedGeneration: PasswordStateManager.getKnownGeneration(),
        );
        await MasterKeyLocalStore.write(
          local.copyWith(
            remoteRecoveryStatus: RemoteRecoveryStatus.published,
            repository: repository,
            clearPreviousPublishedRecoveryWrap: true,
          ),
        );
        await PasswordStateManager.initializeOrJoinState(
          service: service,
          allowCreateInitialState: true,
        );
        return;
      }

      if (mnemonicWords.isEmpty) {
        throw StateError(
          'recovery phrase is required to validate an existing remote recovery wrapper',
        );
      }
      final Uint8List? remoteKey =
          await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
        wrapJson: remoteWrap,
        rawPassword: password,
        mnemonicWords: mnemonicWords,
      );
      if (remoteKey == null || !_constantTimeEquals(localKey, remoteKey)) {
        await MasterKeyLocalStore.write(
          local.copyWith(
            remoteRecoveryStatus: RemoteRecoveryStatus.conflict,
            repository: repository,
          ),
        );
        if (remoteKey != null) zeroBytes(remoteKey);
        throw StateError('remote recovery wrapper resolves to a different Master Key');
      }
      zeroBytes(remoteKey);
      await MasterKeyLocalStore.write(
        local.copyWith(
          remoteRecoveryStatus: RemoteRecoveryStatus.published,
          repository: repository,
          clearPreviousPublishedRecoveryWrap: true,
        ),
      );
      await PasswordStateManager.initializeOrJoinState(
        service: service,
        allowCreateInitialState: true,
      );
    } on GithubFileAlreadyExists {
      final Map<String, dynamic>? racedRemote =
          await service.fetchNoteFile('device_key.json');
      if (racedRemote == null) rethrow;
      await _associateWithObservedRemote(
        service: service,
        local: local,
        localKey: localKey,
        password: password,
        mnemonicWords: mnemonicWords,
        repository: repository,
        remote: racedRemote,
      );
    } finally {
      zeroBytes(localKey);
    }
  }

  Future<void> _associateWithObservedRemote({
    required GithubBackupService service,
    required MasterKeyLocalRecord local,
    required Uint8List localKey,
    required String password,
    required List<String> mnemonicWords,
    required String? repository,
    required Map<String, dynamic> remote,
  }) async {
    final String remoteWrap = jsonEncode(remote);
    if (remoteWrap == local.recoveryWrap) {
      await MasterKeyLocalStore.write(local.copyWith(
        remoteRecoveryStatus: RemoteRecoveryStatus.published,
        repository: repository,
        clearPreviousPublishedRecoveryWrap: true,
      ));
      await PasswordStateManager.initializeOrJoinState(
        service: service,
        allowCreateInitialState: true,
      );
      return;
    }

    if (local.remoteRecoveryStatus == RemoteRecoveryStatus.unpublished &&
        local.previousPublishedRecoveryWrap != null) {
      if (remoteWrap != local.previousPublishedRecoveryWrap) {
        final bool remoteAlreadyCommitted = await _remoteWrapMatchesKey(
          remoteWrap,
          password,
          mnemonicWords,
          localKey,
        );
        if (!remoteAlreadyCommitted) {
          await MasterKeyLocalStore.write(local.copyWith(
            remoteRecoveryStatus: RemoteRecoveryStatus.conflict,
            repository: repository,
          ));
          throw StateError(
            'remote recovery metadata conflicts with the pending local password rotation',
          );
        }
        await MasterKeyLocalStore.write(local.copyWith(
          remoteRecoveryStatus: RemoteRecoveryStatus.published,
          repository: repository,
          clearPreviousPublishedRecoveryWrap: true,
        ));
        await PasswordStateManager.initializeOrJoinState(
          service: service,
          allowCreateInitialState: true,
        );
        return;
      }
      await PasswordStateManager.publishRotationAtomically(
        service: service,
        recoveryWrap: local.recoveryWrap,
        expectedGeneration: PasswordStateManager.getKnownGeneration(),
      );
      await MasterKeyLocalStore.write(local.copyWith(
        remoteRecoveryStatus: RemoteRecoveryStatus.published,
        repository: repository,
        clearPreviousPublishedRecoveryWrap: true,
      ));
      await PasswordStateManager.initializeOrJoinState(
        service: service,
        allowCreateInitialState: true,
      );
      return;
    }

    if (mnemonicWords.isEmpty) {
      throw StateError(
        'recovery phrase is required to validate an existing remote recovery wrapper',
      );
    }
    final Uint8List? remoteKey =
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
      wrapJson: remoteWrap,
      rawPassword: password,
      mnemonicWords: mnemonicWords,
    );
    if (remoteKey == null || !_constantTimeEquals(localKey, remoteKey)) {
      if (remoteKey != null) zeroBytes(remoteKey);
      await MasterKeyLocalStore.write(local.copyWith(
        remoteRecoveryStatus: RemoteRecoveryStatus.conflict,
        repository: repository,
      ));
      throw StateError('remote recovery wrapper resolves to a different Master Key');
    }
    zeroBytes(remoteKey);
    await MasterKeyLocalStore.write(local.copyWith(
      remoteRecoveryStatus: RemoteRecoveryStatus.published,
      repository: repository,
      clearPreviousPublishedRecoveryWrap: true,
    ));
    await PasswordStateManager.initializeOrJoinState(
      service: service,
      allowCreateInitialState: true,
    );
  }

  Future<PasswordChangeResult> changePassword({
    required String oldPassword,
    required String newPassword,
    required List<String> mnemonicWords,
  }) {
    return _runAuthorityMutation<PasswordChangeResult>(
      () => _changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
        mnemonicWords: mnemonicWords,
      ),
    );
  }

  Future<PasswordChangeResult> _changePassword({
    required String oldPassword,
    required String newPassword,
    required List<String> mnemonicWords,
  }) async {
    final MasterKeyLocalRecord? local = await MasterKeyLocalStore.read();
    if (local == null) {
      throw StateError('local Master Key authority is not established');
    }

    final MasterKeyManager manager = MasterKeyManager.instance;
    if (manager.state == MasterKeyState.none) {
      await MasterKeyManager.instance.runExclusiveInitialization<void>(
        (lease) => _restoreFromLocal(
          local,
          oldPassword,
          mnemonicWords,
          initializationLease: lease,
        ),
      );
    } else if (manager.state == MasterKeyState.authoritative) {
      // A password mutation is only allowed from a cryptographically coherent
      // local authority record. Validate BOTH wrappers, not just the password
      // wrapper, before changing anything.
      final Uint8List localKey = await _validateLocalAuthorityRecord(
        local,
        oldPassword,
        mnemonicWords,
      );
      try {
        final Uint8List active = manager.requireAuthoritativeMasterKeyBytes();
        try {
          if (!_constantTimeEquals(localKey, active)) {
            throw StateError(
              'local security record does not match the authoritative in-memory Master Key',
            );
          }
        } finally {
          zeroBytes(active);
        }
      } finally {
        zeroBytes(localKey);
      }
    } else {
      throw StateError('Master Key is provisional; password change is not permitted');
    }

    final PasswordChangeResult? result =
        await PasswordKeyDerivation.changePassword(
      existingPasswordWrapJson: local.passwordWrap,
      existingRecoveryWrapJson: local.recoveryWrap,
      oldRawPassword: oldPassword,
      newRawPassword: newPassword,
      mnemonicWords: mnemonicWords,
    );
    if (result == null) {
      throw StateError('password change authentication failed');
    }

    final Uint8List? newKey =
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
      wrapJson: result.newPasswordWrapJson,
      rawPassword: newPassword,
    );
    if (newKey == null) {
      throw StateError('new Password-KEK wrapper validation failed');
    }
    try {
      final Uint8List active = manager.requireAuthoritativeMasterKeyBytes();
      try {
        if (!_constantTimeEquals(active, newKey)) {
          throw StateError(
            'password change attempted to replace the authoritative Master Key',
          );
        }
      } finally {
        zeroBytes(active);
      }
    } finally {
      zeroBytes(newKey);
    }

    final MasterKeyLocalRecord next = local.copyWith(
      passwordVerifier: result.newVerifier,
      passwordWrap: result.newPasswordWrapJson,
      recoveryWrap: result.newRecoveryWrapJson,
      remoteRecoveryStatus: local.remoteRecoveryStatus ==
              RemoteRecoveryStatus.published
          ? RemoteRecoveryStatus.unpublished
          : local.remoteRecoveryStatus,
      previousPublishedRecoveryWrap: local.remoteRecoveryStatus ==
              RemoteRecoveryStatus.published
          ? local.recoveryWrap
          : local.previousPublishedRecoveryWrap,
    );
    await MasterKeyLocalStore.write(next);
    final MasterKeyLocalRecord? readBack = await MasterKeyLocalStore.read();
    if (readBack == null ||
        readBack.passwordWrap != result.newPasswordWrapJson ||
        readBack.recoveryWrap != result.newRecoveryWrapJson ||
        readBack.passwordVerifier != result.newVerifier) {
      throw StateError('password change local commit verification failed');
    }
    return result;
  }

  Future<T> _runAuthorityMutation<T>(Future<T> Function() operation) async {
    final Future<void> previous = _authorityMutationTail;
    final Completer<T> completer = Completer<T>();
    _authorityMutationTail = () async {
      try {
        await previous;
      } catch (_) {
        // A failed prior mutation must not prevent later mutations from being
        // attempted; the caller of that prior mutation already received its
        // error through its own future.
      }
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  static Future<bool> _remoteWrapMatchesKey(
    String remoteWrap,
    String password,
    List<String> mnemonicWords,
    Uint8List expected,
  ) async {
    final Uint8List? candidate =
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
      wrapJson: remoteWrap,
      rawPassword: password,
      mnemonicWords: mnemonicWords,
    );
    if (candidate == null) return false;
    try {
      return _constantTimeEquals(candidate, expected);
    } finally {
      zeroBytes(candidate);
    }
  }

  static Future<Uint8List> _validateLocalAuthorityRecord(
    MasterKeyLocalRecord record,
    String password,
    List<String> mnemonicWords,
  ) async {
    record.validate();
    if (!await PasswordKeyDerivation.verifyPassword(
      password,
      record.passwordVerifier,
    )) {
      throw StateError('local password authentication failed');
    }

    final Uint8List? passwordKey =
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
      wrapJson: record.passwordWrap,
      rawPassword: password,
    );
    if (passwordKey == null ||
        passwordKey.length != MasterKeyManager.masterKeyLengthBytes) {
      if (passwordKey != null) zeroBytes(passwordKey);
      throw StateError(
        'local Password-KEK wrapper is invalid; refusing to trust local authority',
      );
    }

    final Uint8List? recoveryKey =
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
      wrapJson: record.recoveryWrap,
      rawPassword: password,
      mnemonicWords: mnemonicWords,
    );
    if (recoveryKey == null ||
        recoveryKey.length != MasterKeyManager.masterKeyLengthBytes) {
      zeroBytes(passwordKey);
      if (recoveryKey != null) zeroBytes(recoveryKey);
      throw StateError(
        'local Recovery-KEK wrapper is invalid; refusing to trust local authority',
      );
    }

    if (!_constantTimeEquals(passwordKey, recoveryKey)) {
      zeroBytes(passwordKey);
      zeroBytes(recoveryKey);
      throw StateError(
        'local Password-KEK and Recovery-KEK wrappers resolve to different Master Keys',
      );
    }

    zeroBytes(recoveryKey);
    return passwordKey;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  static Future<bool> _remoteRecoveryMatches(
    Map<String, dynamic> remote,
    String password,
    List<String> mnemonicWords,
    Uint8List expected,
  ) async {
    final Uint8List? candidate =
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
      wrapJson: jsonEncode(remote),
      rawPassword: password,
      mnemonicWords: mnemonicWords,
    );
    if (candidate == null) return false;
    try {
      return _constantTimeEquals(candidate, expected);
    } finally {
      zeroBytes(candidate);
    }
  }
}
