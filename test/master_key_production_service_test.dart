import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/domain_key_derivation.dart';
import 'package:rocen/core/github_backup_service.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/password_key_derivation.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/fake_github_remote.dart';
import 'support/activation_contract.dart';

const List<String> _mnemonic = [
  'abandon',
  'ability',
  'able',
  'about',
  'above',
  'absent',
  'absorb',
  'abstract',
  'absurd',
  'abuse',
  'access',
  'accident',
];

/// Real authenticated-session capability for Stage 3 mechanics tests: a REAL
/// unlock against the REAL durable record created by establishFirstDevice
/// (real password verify, real Argon2id unwrap, real HKDF), then the real
/// token. There is no test-only entry point: the operations under test are
/// the same public, token-requiring methods production uses.
Future<SessionAuthorizationToken> _tokenFor(String password) async {
  final ssm = SessionSecurityManager.instance;
  ssm.lockSync();
  if (ssm.state == SessionState.bootstrap) ssm.finishBootstrap();
  await ssm.unlock(
    password: password,
    activateRoot: satisfyActivationContract,
    teardownRoot: () {},
  );
  return ssm.captureAuthorization();
}

Future<void> _rawPutRecord(MasterKeyLocalRecord record) async {
  // Scenario setup only: writes the serialized record straight into the Hive
  // box (the genuine storage primitive). There is no public MasterKeyLocalStore
  // write API any more.
  await Hive.box(MasterKeyLocalStore.boxName)
      .put(MasterKeyLocalStore.recordKey, record.toJsonString());
}

Uint8List _fixedMasterKey(int seed) => Uint8List.fromList(
      List<int>.generate(32, (i) => (seed + (i * 29)) & 0xFF),
    );

Future<String> _recoveryWrap(Uint8List mk, String password) =>
    PasswordKeyDerivation.wrapMasterKeyWithRecovery(
      masterKeyBytes: mk,
      rawPassword: password,
      mnemonicWords: _mnemonic,
    );

/// MasterKeyManager no longer holds Master Key bytes (Stage 5 single-owner
/// invariant), so tests observe "the MK" the same way a real unlock does: by
/// independently unwrapping the durable record's Password-KEK wrapper. This
/// keeps every Stage 3 assertion (same MK across restart / password change /
/// recovery / conflict) intact while removing the dependency on a retained
/// in-memory copy.
Future<Uint8List> _observedMk(String password) async {
  final MasterKeyLocalRecord record = (await MasterKeyLocalStore.read())!;
  final Uint8List? key =
      await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
    wrapJson: record.passwordWrap,
    rawPassword: password,
  );
  return key!;
}

Future<List<int>> _deriveNek(Uint8List mk) async {
  final key = await DomainKeyDerivation.deriveNoteEncryptionKey(mk);
  try {
    return List<int>.from(key.bytes);
  } finally {
    key.zero();
  }
}

Future<List<int>> _deriveTek(Uint8List mk) async {
  final key = await DomainKeyDerivation.deriveGithubTokenEncryptionKey(mk);
  try {
    return List<int>.from(key.bytes);
  } finally {
    key.zero();
  }
}

Future<void> main() async {
  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('rocen_master_service_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    SessionSecurityManager.instance.resetForTesting();
    MasterKeyManager.instance.resetForTesting();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    enableSimulatedScreenAcknowledgementForTest();
  });

  tearDown(() => SessionSecurityManager.instance.lockSync());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('firstDeviceGeneratesOneMK and establishes local authority', () async {
    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );

    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(MasterKeyManager.instance.isInitializationInFlight, isFalse);
    final key = await _observedMk('BlockB!Password44');
    try {
      expect(key.length, 32);
    } finally {
      key.fillRange(0, key.length, 0);
    }

    final record = await MasterKeyLocalStore.read();
    expect(record, isNotNull);
    expect(record!.authority, 'authoritative');
    expect(record.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished);
    expect(record.repository, isNull);
  });

  test('sameMKAcrossBothWrappers and passwordVerifierAreValid', () async {
    const password = 'BlockB!Password44';
    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
    );
    final record = await MasterKeyLocalStore.read();
    expect(record, isNotNull);

    final passwordKey = await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
      wrapJson: record!.passwordWrap,
      rawPassword: password,
    );
    final recoveryKey = await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
      wrapJson: record.recoveryWrap,
      rawPassword: password,
      mnemonicWords: _mnemonic,
    );
    try {
      expect(passwordKey, isNotNull);
      expect(recoveryKey, isNotNull);
      expect(passwordKey, recoveryKey);
      expect(
        await PasswordKeyDerivation.verifyPassword(
          password,
          record.passwordVerifier,
        ),
        isTrue,
      );
      expect(
        await PasswordKeyDerivation.verifyPassword(
          'Wrong!Password55',
          record.passwordVerifier,
        ),
        isFalse,
      );
    } finally {
      if (passwordKey != null) {
        passwordKey.fillRange(0, passwordKey.length, 0);
      }
      if (recoveryKey != null) {
        recoveryKey.fillRange(0, recoveryKey.length, 0);
      }
    }
  });

  test('localAuthorityPersistsAcrossRestart with the SAME MK', () async {
    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );
    final MasterKeyLocalRecord? beforeRestart =
        await MasterKeyLocalStore.read();
    final before = await _observedMk('BlockB!Password44');
    final beforeCopy = List<int>.from(before);
    before.fillRange(0, before.length, 0);

    MasterKeyManager.instance.resetForTesting();
    SessionSecurityManager.instance.lockSync();
    // A restart retains the durable authority. Re-running the bootstrap-only
    // first-device operation is correctly refused once that authority exists.
    final MasterKeyLocalRecord? afterRestart =
        await MasterKeyLocalStore.read();
    expect(afterRestart, isNotNull);
    expect(afterRestart!.isSamePersistedRecordAs(beforeRestart!), isTrue);
    final after = await _observedMk('BlockB!Password44');
    try {
      expect(after, beforeCopy);
    } finally {
      after.fillRange(0, after.length, 0);
    }
  });

  test('wrongPasswordDoesNotRestoreLocalMK', () async {
    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );
    MasterKeyManager.instance.resetForTesting();

    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: 'Wrong!Password55',
        mnemonicWords: _mnemonic,
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
  });

  test('restartReconcilesAlreadyCommittedPasswordRotation', () async {
    const oldPassword = 'BlockB!Password44';
    const newPassword = 'BlockB!Password55';
    final remote = FakeGithubRemote();

    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: oldPassword,
      mnemonicWords: _mnemonic,
    );
    final oldRecord = await MasterKeyLocalStore.read();
    expect(oldRecord, isNotNull);
    remote.seed('device_key.json', oldRecord!.recoveryWrap);
    await MasterKeyProductionService.instance.associateRemote(
      authorizationToken: await _tokenFor(oldPassword),
      service: remote.service,
      password: oldPassword,
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    final result = await MasterKeyProductionService.instance.changePassword(
      authorizationToken: await _tokenFor(oldPassword),
      oldPassword: oldPassword,
      newPassword: newPassword,
      mnemonicWords: _mnemonic,
    );
    final pending = await MasterKeyLocalStore.read();
    expect(pending!.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished);

    // Simulate that GitHub committed the new recovery wrapper, but local
    // finalization did not happen before process termination.
    remote.files['device_key.json'] = result.newRecoveryWrapJson;
    remote.branchSha = 'sha-committed-rotation';
    MasterKeyManager.instance.resetForTesting();

    // Reconciliation of an established account is an AUTHENTICATED operation
    // (bootstrap-only establishFirstDevice refuses an existing account).
    await MasterKeyProductionService.instance.associateRemote(
      authorizationToken: await _tokenFor(newPassword),
      service: remote.service,
      password: newPassword,
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    final recovered = await MasterKeyLocalStore.read();
    expect(recovered!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(recovered.previousPublishedRecoveryWrap, isNull);
  });

  test('passwordChangeRejectsCorruptedRecoveryWrapperBeforeMutation', () async {
    const password = 'BlockB!Password44';
    const newPassword = 'BlockB!Password55';
    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
    );
    final record = await MasterKeyLocalStore.read();
    expect(record, isNotNull);

    final otherMk = _fixedMasterKey(91);
    final mismatchedRecoveryWrap = await _recoveryWrap(otherMk, password);
    await _rawPutRecord(
      record!.copyWith(recoveryWrap: mismatchedRecoveryWrap),
    );
    otherMk.fillRange(0, otherMk.length, 0);

    await expectLater(
      MasterKeyProductionService.instance.changePassword(
        authorizationToken: await _tokenFor(password),
        oldPassword: password,
        newPassword: newPassword,
        mnemonicWords: _mnemonic,
      ),
      throwsStateError,
    );

    final unchanged = await MasterKeyLocalStore.read();
    expect(unchanged!.passwordWrap, record.passwordWrap);
    expect(unchanged.recoveryWrap, mismatchedRecoveryWrap);
    expect(unchanged.passwordVerifier, record.passwordVerifier);
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(MasterKeyManager.instance.isInitializationInFlight, isFalse);
  });

  test('authorityMutationsAreSerializedAndStalePasswordChangeCannotOverwrite',
      () async {
    const oldPassword = 'BlockB!Password44';
    const newPasswordA = 'BlockB!Password55';
    const newPasswordB = 'BlockB!Password66';
    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: oldPassword,
      mnemonicWords: _mnemonic,
    );

    final token = await _tokenFor(oldPassword);
    final Future<bool> first = MasterKeyProductionService.instance
        .changePassword(
          authorizationToken: token,
          oldPassword: oldPassword,
          newPassword: newPasswordA,
          mnemonicWords: _mnemonic,
        )
        .then<bool>((_) => true, onError: (_, __) => false);
    final Future<bool> second = MasterKeyProductionService.instance
        .changePassword(
          authorizationToken: token,
          oldPassword: oldPassword,
          newPassword: newPasswordB,
          mnemonicWords: _mnemonic,
        )
        .then<bool>((_) => true, onError: (_, __) => false);

    final List<bool> outcomes = await Future.wait<bool>([first, second]);
    expect(outcomes.where((value) => value).length, 1);
    expect(outcomes.where((value) => !value).length, 1);

    final finalRecord = await MasterKeyLocalStore.read();
    expect(finalRecord, isNotNull);
    expect(finalRecord!.revision, 2);
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(MasterKeyManager.instance.isInitializationInFlight, isFalse);
  });

  test('passwordChangePreservesMK_NEK_and_TEK', () async {
    const oldPassword = 'BlockB!Password44';
    const newPassword = 'BlockB!Password55';
    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: oldPassword,
      mnemonicWords: _mnemonic,
    );
    final mkBefore = await _observedMk(oldPassword);
    final mkBeforeCopy = List<int>.from(mkBefore);
    final nekBeforeCopy = await _deriveNek(mkBefore);
    final tekBeforeCopy = await _deriveTek(mkBefore);
    mkBefore.fillRange(0, mkBefore.length, 0);

    final result = await MasterKeyProductionService.instance.changePassword(
      authorizationToken: await _tokenFor(oldPassword),
      oldPassword: oldPassword,
      newPassword: newPassword,
      mnemonicWords: _mnemonic,
    );

    // Observe through the NEW password: the same MK must now be reachable
    // via the rewrapped Password-KEK wrapper, and the frozen Stage 4
    // derivation of it must be unchanged.
    final mkAfter = await _observedMk(newPassword);
    final nekAfter = await _deriveNek(mkAfter);
    final tekAfter = await _deriveTek(mkAfter);
    try {
      expect(mkAfter, mkBeforeCopy);
      expect(nekAfter, nekBeforeCopy);
      expect(tekAfter, tekBeforeCopy);
      final newPasswordKey =
          await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
        wrapJson: result.newPasswordWrapJson,
        rawPassword: newPassword,
      );
      expect(newPasswordKey, isNotNull);
      if (newPasswordKey != null) {
        newPasswordKey.fillRange(0, newPasswordKey.length, 0);
      }
      final newRecoveryKey =
          await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
        wrapJson: result.newRecoveryWrapJson,
        rawPassword: newPassword,
        mnemonicWords: _mnemonic,
      );
      expect(newRecoveryKey, isNotNull);
      if (newRecoveryKey != null) {
        newRecoveryKey.fillRange(0, newRecoveryKey.length, 0);
      }
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
          wrapJson: result.newPasswordWrapJson,
          rawPassword: oldPassword,
        ),
        isNull,
      );
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
          wrapJson: result.newRecoveryWrapJson,
          rawPassword: oldPassword,
          mnemonicWords: _mnemonic,
        ),
        isNull,
      );
      expect(
        await PasswordKeyDerivation.verifyPassword(
          newPassword,
          result.newVerifier,
        ),
        isTrue,
      );
      expect(
        await PasswordKeyDerivation.verifyPassword(
          oldPassword,
          result.newVerifier,
        ),
        isFalse,
      );
    } finally {
      mkAfter.fillRange(0, mkAfter.length, 0);
    }

    final local = await MasterKeyLocalStore.read();
    expect(local!.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished);
  });

  test('mismatchedLocalWrappersRejectAuthorityWithoutReplacement', () async {
    const password = 'BlockB!Password44';
    final mkA = _fixedMasterKey(31);
    final mkB = _fixedMasterKey(37);
    final passwordWrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
      masterKeyBytes: mkA,
      rawPassword: password,
    );
    final recoveryWrap = await _recoveryWrap(mkB, password);
    final verifier =
        await PasswordKeyDerivation.createPasswordVerifier(password);
    await _rawPutRecord(
      MasterKeyLocalRecord.authoritative(
        passwordVerifier: verifier,
        passwordWrap: passwordWrap,
        recoveryWrap: recoveryWrap,
        remoteRecoveryStatus: RemoteRecoveryStatus.unpublished,
      ),
    );

    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: password,
        mnemonicWords: _mnemonic,
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    // The bootstrap path refused an ESTABLISHED (even if mismatched) account
    // before any mutation; the authenticated path validates the wrappers.
    final token = await _tokenFor(password);
    await expectLater(
      MasterKeyProductionService.instance.associateRemote(
        authorizationToken: token,
        service: FakeGithubRemote().service,
        password: password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    final persisted = await MasterKeyLocalStore.read();
    expect(persisted!.passwordWrap, passwordWrap);
    expect(persisted.recoveryWrap, recoveryWrap);
    mkA.fillRange(0, mkA.length, 0);
    mkB.fillRange(0, mkB.length, 0);
  });

  test('recoverSameMKFromRemoteWrapper', () async {
    final remote = FakeGithubRemote();
    final expected = _fixedMasterKey(7);
    final recoveryWrap = await _recoveryWrap(expected, 'BlockB!Password44');
    remote.seed('device_key.json', recoveryWrap);

    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.recoverFromRemote(
      service: remote.service,
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    final actual = await _observedMk('BlockB!Password44');
    try {
      expect(actual, expected);
    } finally {
      actual.fillRange(0, actual.length, 0);
      expected.fillRange(0, expected.length, 0);
    }
    final local = await MasterKeyLocalStore.read();
    expect(local!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
  });

  test('wrongPasswordDoesNotInstallMK during remote recovery', () async {
    final remote = FakeGithubRemote();
    final expected = _fixedMasterKey(11);
    remote.seed(
        'device_key.json', await _recoveryWrap(expected, 'BlockB!Password44'));

    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.recoverFromRemote(
        service: remote.service,
        password: 'Wrong!Password55',
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(await MasterKeyLocalStore.read(), isNull);
    expected.fillRange(0, expected.length, 0);
  });

  test('wrongMnemonicDoesNotInstallMK during remote recovery', () async {
    final remote = FakeGithubRemote();
    final expected = _fixedMasterKey(13);
    remote.seed(
        'device_key.json', await _recoveryWrap(expected, 'BlockB!Password44'));
    final wrongMnemonic = List<String>.from(_mnemonic)..[0] = 'zoo';

    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.recoverFromRemote(
        service: remote.service,
        password: 'BlockB!Password44',
        mnemonicWords: wrongMnemonic,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(await MasterKeyLocalStore.read(), isNull);
    expected.fillRange(0, expected.length, 0);
  });

  test('tamperedWrapperRejected without replacementMK', () async {
    final remote = FakeGithubRemote();
    final expected = _fixedMasterKey(17);
    final valid = await _recoveryWrap(expected, 'BlockB!Password44');
    final decoded = jsonDecode(valid) as Map<String, dynamic>;
    final ct = decoded['ct'] as String;
    decoded['ct'] =
        ct.substring(0, ct.length - 1) + (ct.endsWith('A') ? 'B' : 'A');
    remote.seed('device_key.json', jsonEncode(decoded));

    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.recoverFromRemote(
        service: remote.service,
        password: 'BlockB!Password44',
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(await MasterKeyLocalStore.read(), isNull);
    expected.fillRange(0, expected.length, 0);
  });

  test('malformedAndUnsupportedWrappersDoNotInstallMK', () async {
    for (final malformed in <String>[
      '{"v":1,"kdf":"argon2id"}',
      '{"v":2,"kdf":"argon2id","memory":65536,"iterations":3,"salt":"","nonce":"","ct":"","mac":""}',
      'not-json',
    ]) {
      MasterKeyManager.instance.resetForTesting();
      await Hive.box(MasterKeyLocalStore.boxName).clear();
      final remote = FakeGithubRemote();
      remote.seed('device_key.json', malformed);
      SessionSecurityManager.instance.lockSync();
      await expectLater(
        MasterKeyProductionService.instance.recoverFromRemote(
          service: remote.service,
          password: 'BlockB!Password44',
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
        ),
        throwsA(anyOf(isA<StateError>(), isA<GithubSyncException>())),
      );
      expect(MasterKeyManager.instance.state, MasterKeyState.none);
      expect(await MasterKeyLocalStore.read(), isNull);
    }
  });

  test('remoteExistingDifferentMKProducesConflict without replacement',
      () async {
    final remote = FakeGithubRemote();
    final remoteMk = _fixedMasterKey(19);
    remote.seed(
        'device_key.json', await _recoveryWrap(remoteMk, 'Local!Password77'));

    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'Local!Password77',
      mnemonicWords: _mnemonic,
    );
    final localBefore = await _observedMk('Local!Password77');
    final localBeforeCopy = List<int>.from(localBefore);
    localBefore.fillRange(0, localBefore.length, 0);

    await expectLater(
      MasterKeyProductionService.instance.associateRemote(
        authorizationToken: await _tokenFor('Local!Password77'),
        service: remote.service,
        password: 'Local!Password77',
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );

    final localAfter = await _observedMk('Local!Password77');
    final record = await MasterKeyLocalStore.read();
    try {
      expect(localAfter, localBeforeCopy);
      expect(record!.remoteRecoveryStatus, RemoteRecoveryStatus.conflict);
    } finally {
      localAfter.fillRange(0, localAfter.length, 0);
      remoteMk.fillRange(0, remoteMk.length, 0);
    }
  });

  test('remoteConflictSurvivesRestart', () async {
    const password = 'Local!Password77';
    final remote = FakeGithubRemote();
    final remoteMk = _fixedMasterKey(43);
    remote.seed('device_key.json', await _recoveryWrap(remoteMk, password));

    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
    );
    await expectLater(
      MasterKeyProductionService.instance.associateRemote(
        authorizationToken: await _tokenFor(password),
        service: remote.service,
        password: password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    final conflict = await MasterKeyLocalStore.read();
    expect(conflict!.remoteRecoveryStatus, RemoteRecoveryStatus.conflict);

    MasterKeyManager.instance.resetForTesting();
    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: password,
        mnemonicWords: _mnemonic,
      ),
      throwsStateError,
    );
    final persistedConflict = await MasterKeyLocalStore.read();
    expect(
        persistedConflict!.remoteRecoveryStatus, RemoteRecoveryStatus.conflict);

    remoteMk.fillRange(0, remoteMk.length, 0);
  });

  test('sameMKAssociatesExistingRemote', () async {
    final remote = FakeGithubRemote();
    const password = 'BlockB!Password44';
    SessionSecurityManager.instance.lockSync();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
    );
    final local = await MasterKeyLocalStore.read();
    remote.seed('device_key.json', local!.recoveryWrap);

    await MasterKeyProductionService.instance.associateRemote(
      authorizationToken: await _tokenFor(password),
      service: remote.service,
      password: password,
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    final after = await MasterKeyLocalStore.read();
    expect(after!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(remote.files.containsKey('password_state.json'), isTrue);
  });

  test('existingRemoteAuthorityIsDiscoveredBeforeFreshGeneration', () async {
    final remote = FakeGithubRemote();
    remote.seed('some_other_file.json', '{"legacy":true}');

    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: 'BlockB!Password44',
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(await MasterKeyLocalStore.read(), isNull);
    expect(remote.files.containsKey('device_key.json'), isFalse);
  });

  test('retryAfterRemoteFailureDoesNotGenerateSecondMK', () async {
    final remote = FakeGithubRemote()..failCreateOnce = true;
    const password = 'BlockB!Password44';

    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      ),
      throwsA(isA<GithubSyncException>()),
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);

    final failedRecord = await MasterKeyLocalStore.read();
    expect(failedRecord, isNotNull);
    expect(
        failedRecord!.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished);

    // Retry on the ESTABLISHED account is authenticated (token), never a
    // second bootstrap.
    await MasterKeyProductionService.instance.associateRemote(
      authorizationToken: await _tokenFor(password),
      service: remote.service,
      password: password,
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(MasterKeyManager.instance.isInitializationInFlight, isFalse);
    final retriedRecord = await MasterKeyLocalStore.read();
    expect(retriedRecord!.recoveryWrap, failedRecord.recoveryWrap);
    expect(retriedRecord.remoteRecoveryStatus, RemoteRecoveryStatus.published);
  });

  test('remoteSuccessLocalFinalizeFailureCanBeRecoveredWithoutNewMK', () async {
    final remote = FakeGithubRemote()..failPasswordStateUpdateOnce = true;
    const password = 'BlockB!Password44';

    SessionSecurityManager.instance.lockSync();
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      ),
      throwsA(isA<GithubSyncException>()),
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    final recordAfterFailure = await MasterKeyLocalStore.read();
    expect(recordAfterFailure!.remoteRecoveryStatus,
        RemoteRecoveryStatus.unpublished,
        reason: 'the shared-state commit failed, so publication is incomplete');
    expect(remote.files.containsKey('device_key.json'), isTrue);

    // Simulate process restart: the in-memory MK disappears, so reconciliation
    // must restore the same persisted local authority and never generate a new key.
    MasterKeyManager.instance.resetForTesting();
    await MasterKeyProductionService.instance.associateRemote(
      authorizationToken: await _tokenFor(password),
      service: remote.service,
      password: password,
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(MasterKeyManager.instance.isInitializationInFlight, isFalse);
    final retried = await MasterKeyLocalStore.read();
    expect(retried!.recoveryWrap, recordAfterFailure.recoveryWrap);
    expect(retried.remoteRecoveryStatus, RemoteRecoveryStatus.published);
  });

  test(
      'twoConcurrentFirstDeviceCalls: serialized; the second sees the '
      'established authority and is refused without mutating it', () async {
    final remote = FakeGithubRemote();
    SessionSecurityManager.instance.lockSync();
    final first = MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
      remoteService: remote.service,
      repository: 'owner/repo',
    );
    final second = MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
      remoteService: remote.service,
      repository: 'owner/repo',
    );
    second.ignore();

    await first;
    await expectLater(second, throwsA(isA<BootstrapNotEligibleException>()));
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(MasterKeyManager.instance.isInitializationInFlight, isFalse);
    final record = await MasterKeyLocalStore.read();
    expect(record!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(record.revision, greaterThanOrEqualTo(1));
    expect(remote.files.containsKey('device_key.json'), isTrue);
  });

  test('staleRemoteRefRejected (generic write path, non-reserved file)',
      () async {
    final remote = FakeGithubRemote();
    remote.seed('notes/a.json', '{"v":1}');
    final stale = remote.branchSha;
    remote.seed('notes/b.json', '{"n":1}');
    remote.branchSha = 'sha-moved';
    expect(remote.branchSha, isNot(stale));

    await expectLater(
      remote.service.updateFilesWithFastForwardCheck(
        updates: {'notes/a.json': '{"v":2}'},
        message: 'stale test',
        expectedParentSha: stale,
      ),
      throwsA(isA<GithubConditionalWriteConflict>()),
    );
  });
}
