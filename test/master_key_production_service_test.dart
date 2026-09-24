import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Rocen/core/domain_key_derivation.dart';
import 'package:Rocen/core/github_backup_service.dart';
import 'package:Rocen/core/master_key_local_store.dart';
import 'package:Rocen/core/master_key_manager.dart';
import 'package:Rocen/core/master_key_production_service.dart';
import 'package:Rocen/core/password_key_derivation.dart';

const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

Uint8List _fixedMasterKey(int seed) => Uint8List.fromList(
      List<int>.generate(32, (i) => (seed + (i * 29)) & 0xFF),
    );

class FakeGithubBackupService extends GithubBackupService {
  FakeGithubBackupService({super.token = 'test-token', super.repoPath = 'owner/repo'})
      : super(branch: 'main');

  final Map<String, String> files = <String, String>{};
  String? branchSha;
  int _shaCounter = 0;
  bool failCreateOnce = false;
  bool failPasswordStateUpdateOnce = false;

  String _nextSha() => 'sha-${++_shaCounter}';

  void seed(String path, String content) {
    files[path] = content;
    branchSha ??= _nextSha();
  }

  Future<void> seedDifferentRemoteDataset(Uint8List mk, String password) async {
    seed(
      'device_key.json',
      await _recoveryWrap(mk, password),
    );
  }

  @override
  Future<({Map<String, dynamic>? content, String? refSha})>
      fetchNoteFileWithRefSha(String fileName) async {
    final raw = files[fileName];
    return (
      content: raw == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(raw) as Map),
      refSha: branchSha,
    );
  }

  @override
  Future<Map<String, dynamic>?> fetchNoteFile(String fileName) async {
    final raw = files[fileName];
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> createFileIfAbsent({
    required String path,
    required String content,
    required String message,
  }) async {
    if (failCreateOnce) {
      failCreateOnce = false;
      throw GithubSyncException('simulated remote create failure');
    }
    if (files.containsKey(path)) {
      throw GithubFileAlreadyExists('already exists');
    }
    files[path] = content;
    branchSha = _nextSha();
  }

  @override
  Future<void> updateFileWithFastForwardCheck({
    required String path,
    required String content,
    required String message,
    required String? expectedParentSha,
  }) async {
    if (expectedParentSha != branchSha) {
      throw GithubConditionalWriteConflict('stale branch');
    }
    if (path == 'password_state.json' && failPasswordStateUpdateOnce) {
      failPasswordStateUpdateOnce = false;
      throw GithubSyncException('simulated password-state failure');
    }
    files[path] = content;
    branchSha = _nextSha();
  }

  @override
  Future<void> updateFilesWithFastForwardCheck({
    required Map<String, String> updates,
    required String message,
    required String? expectedParentSha,
  }) async {
    if (expectedParentSha != branchSha) {
      throw GithubConditionalWriteConflict('stale branch');
    }
    for (final entry in updates.entries) {
      files[entry.key] = entry.value;
    }
    branchSha = _nextSha();
  }
}

Future<String> _recoveryWrap(Uint8List mk, String password) =>
    PasswordKeyDerivation.wrapMasterKeyWithRecovery(
      masterKeyBytes: mk,
      rawPassword: password,
      mnemonicWords: _mnemonic,
    );

Future<void> main() async {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_master_service_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('firstDeviceGeneratesOneMK and establishes local authority', () async {
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );

    expect(MasterKeyManager.instance.state, MasterKeyState.authoritative);
    final key = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
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
    final recoveryKey =
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
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
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );
    final before = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    final beforeCopy = List<int>.from(before);
    before.fillRange(0, before.length, 0);

    MasterKeyManager.instance.resetForTesting();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );
    final after = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    try {
      expect(after, beforeCopy);
    } finally {
      after.fillRange(0, after.length, 0);
    }
  });

  test('wrongPasswordDoesNotRestoreLocalMK', () async {
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );
    MasterKeyManager.instance.resetForTesting();

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
    final remote = FakeGithubBackupService();

    await MasterKeyProductionService.instance.establishFirstDevice(
      password: oldPassword,
      mnemonicWords: _mnemonic,
    );
    final oldRecord = await MasterKeyLocalStore.read();
    expect(oldRecord, isNotNull);
    remote.seed('device_key.json', oldRecord!.recoveryWrap);
    await MasterKeyProductionService.instance.associateRemote(
      service: remote,
      password: oldPassword,
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    final result = await MasterKeyProductionService.instance.changePassword(
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

    await MasterKeyProductionService.instance.establishFirstDevice(
      password: newPassword,
      mnemonicWords: _mnemonic,
      remoteService: remote,
      repository: 'owner/repo',
    );

    final recovered = await MasterKeyLocalStore.read();
    expect(recovered!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(recovered.previousPublishedRecoveryWrap, isNull);
  });

  test('passwordChangeRejectsCorruptedRecoveryWrapperBeforeMutation', () async {
    const password = 'BlockB!Password44';
    const newPassword = 'BlockB!Password55';
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
    );
    final record = await MasterKeyLocalStore.read();
    expect(record, isNotNull);

    final otherMk = _fixedMasterKey(91);
    final mismatchedRecoveryWrap = await _recoveryWrap(otherMk, password);
    await MasterKeyLocalStore.write(
      record!.copyWith(recoveryWrap: mismatchedRecoveryWrap),
    );
    otherMk.fillRange(0, otherMk.length, 0);

    await expectLater(
      MasterKeyProductionService.instance.changePassword(
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
    expect(MasterKeyManager.instance.state, MasterKeyState.authoritative);
  });

  test('authorityMutationsAreSerializedAndStalePasswordChangeCannotOverwrite', () async {
    const oldPassword = 'BlockB!Password44';
    const newPasswordA = 'BlockB!Password55';
    const newPasswordB = 'BlockB!Password66';
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: oldPassword,
      mnemonicWords: _mnemonic,
    );

    final Future<bool> first = MasterKeyProductionService.instance
        .changePassword(
          oldPassword: oldPassword,
          newPassword: newPasswordA,
          mnemonicWords: _mnemonic,
        )
        .then<bool>((_) => true, onError: (_, __) => false);
    final Future<bool> second = MasterKeyProductionService.instance
        .changePassword(
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
    expect(MasterKeyManager.instance.state, MasterKeyState.authoritative);
  });

  test('passwordChangePreservesMK_NEK_and_TEK', () async {
    const oldPassword = 'BlockB!Password44';
    const newPassword = 'BlockB!Password55';
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: oldPassword,
      mnemonicWords: _mnemonic,
    );
    final mkBefore = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    final mkBeforeCopy = List<int>.from(mkBefore);
    mkBefore.fillRange(0, mkBefore.length, 0);

    final nekBefore = await DomainKeyDerivation.deriveNoteEncryptionKey();
    final tekBefore = await DomainKeyDerivation.deriveGithubTokenEncryptionKey();
    final nekBeforeCopy = List<int>.from(nekBefore.bytes);
    final tekBeforeCopy = List<int>.from(tekBefore.bytes);
    nekBefore.zero();
    tekBefore.zero();

    final result = await MasterKeyProductionService.instance.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
      mnemonicWords: _mnemonic,
    );

    final mkAfter = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    final nekAfter = await DomainKeyDerivation.deriveNoteEncryptionKey();
    final tekAfter = await DomainKeyDerivation.deriveGithubTokenEncryptionKey();
    try {
      expect(mkAfter, mkBeforeCopy);
      expect(nekAfter.bytes, nekBeforeCopy);
      expect(tekAfter.bytes, tekBeforeCopy);
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
      nekAfter.zero();
      tekAfter.zero();
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
    final verifier = await PasswordKeyDerivation.createPasswordVerifier(password);
    await MasterKeyLocalStore.write(
      MasterKeyLocalRecord.authoritative(
        passwordVerifier: verifier,
        passwordWrap: passwordWrap,
        recoveryWrap: recoveryWrap,
        remoteRecoveryStatus: RemoteRecoveryStatus.unpublished,
      ),
    );

    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: password,
        mnemonicWords: _mnemonic,
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    final persisted = await MasterKeyLocalStore.read();
    expect(persisted!.passwordWrap, passwordWrap);
    expect(persisted.recoveryWrap, recoveryWrap);
    mkA.fillRange(0, mkA.length, 0);
    mkB.fillRange(0, mkB.length, 0);
  });

  test('recoverSameMKFromRemoteWrapper', () async {
    final remote = FakeGithubBackupService();
    final expected = _fixedMasterKey(7);
    final recoveryWrap = await _recoveryWrap(expected, 'BlockB!Password44');
    remote.seed('device_key.json', recoveryWrap);

    await MasterKeyProductionService.instance.recoverFromRemote(
      service: remote,
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    final actual = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
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
    final remote = FakeGithubBackupService();
    final expected = _fixedMasterKey(11);
    remote.seed('device_key.json', await _recoveryWrap(expected, 'BlockB!Password44'));

    await expectLater(
      MasterKeyProductionService.instance.recoverFromRemote(
        service: remote,
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
    final remote = FakeGithubBackupService();
    final expected = _fixedMasterKey(13);
    remote.seed('device_key.json', await _recoveryWrap(expected, 'BlockB!Password44'));
    final wrongMnemonic = List<String>.from(_mnemonic)..[0] = 'zoo';

    await expectLater(
      MasterKeyProductionService.instance.recoverFromRemote(
        service: remote,
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
    final remote = FakeGithubBackupService();
    final expected = _fixedMasterKey(17);
    final valid = await _recoveryWrap(expected, 'BlockB!Password44');
    final decoded = jsonDecode(valid) as Map<String, dynamic>;
    final ct = decoded['ct'] as String;
    decoded['ct'] = ct.substring(0, ct.length - 1) +
        (ct.endsWith('A') ? 'B' : 'A');
    remote.seed('device_key.json', jsonEncode(decoded));

    await expectLater(
      MasterKeyProductionService.instance.recoverFromRemote(
        service: remote,
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
      final remote = FakeGithubBackupService();
      remote.seed('device_key.json', malformed);
      await expectLater(
        MasterKeyProductionService.instance.recoverFromRemote(
          service: remote,
          password: 'BlockB!Password44',
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
        ),
        throwsStateError,
      );
      expect(MasterKeyManager.instance.state, MasterKeyState.none);
      expect(await MasterKeyLocalStore.read(), isNull);
    }
  });

  test('remoteExistingDifferentMKProducesConflict without replacement', () async {
    final remote = FakeGithubBackupService();
    final remoteMk = _fixedMasterKey(19);
    await remote.seedDifferentRemoteDataset(remoteMk, 'Local!Password77');

    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'Local!Password77',
      mnemonicWords: _mnemonic,
    );
    final localBefore = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    final localBeforeCopy = List<int>.from(localBefore);
    localBefore.fillRange(0, localBefore.length, 0);

    await expectLater(
      MasterKeyProductionService.instance.associateRemote(
        service: remote,
        password: 'Local!Password77',
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );

    final localAfter = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
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
    final remote = FakeGithubBackupService();
    final remoteMk = _fixedMasterKey(43);
    await remote.seedDifferentRemoteDataset(remoteMk, password);

    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
    );
    await expectLater(
      MasterKeyProductionService.instance.associateRemote(
        service: remote,
        password: password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    final conflict = await MasterKeyLocalStore.read();
    expect(conflict!.remoteRecoveryStatus, RemoteRecoveryStatus.conflict);

    MasterKeyManager.instance.resetForTesting();
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: password,
        mnemonicWords: _mnemonic,
      ),
      throwsStateError,
    );
    final persistedConflict = await MasterKeyLocalStore.read();
    expect(persistedConflict!.remoteRecoveryStatus, RemoteRecoveryStatus.conflict);

    remoteMk.fillRange(0, remoteMk.length, 0);
  });

  test('sameMKAssociatesExistingRemote', () async {
    final remote = FakeGithubBackupService();
    const password = 'BlockB!Password44';
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
    );
    final local = await MasterKeyLocalStore.read();
    remote.seed('device_key.json', local!.recoveryWrap);

    await MasterKeyProductionService.instance.associateRemote(
      service: remote,
      password: password,
      mnemonicWords: _mnemonic,
      repository: 'owner/repo',
    );

    final after = await MasterKeyLocalStore.read();
    expect(after!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(remote.files.containsKey('password_state.json'), isTrue);
  });

  test('existingRemoteAuthorityIsDiscoveredBeforeFreshGeneration', () async {
    final remote = FakeGithubBackupService();
    remote.seed('some_other_file.json', '{"legacy":true}');

    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: 'BlockB!Password44',
        mnemonicWords: _mnemonic,
        remoteService: remote,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(await MasterKeyLocalStore.read(), isNull);
    expect(remote.files.containsKey('device_key.json'), isFalse);
  });

  test('retryAfterRemoteFailureDoesNotGenerateSecondMK', () async {
    final remote = FakeGithubBackupService()..failCreateOnce = true;
    const password = 'BlockB!Password44';

    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: password,
        mnemonicWords: _mnemonic,
        remoteService: remote,
        repository: 'owner/repo',
      ),
      throwsA(isA<GithubSyncException>()),
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);

    final failedRecord = await MasterKeyLocalStore.read();
    expect(failedRecord, isNotNull);
    expect(failedRecord!.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished);

    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
      remoteService: remote,
      repository: 'owner/repo',
    );

    expect(MasterKeyManager.instance.state, MasterKeyState.authoritative);
    final retriedRecord = await MasterKeyLocalStore.read();
    expect(retriedRecord!.recoveryWrap, failedRecord.recoveryWrap);
    expect(retriedRecord.remoteRecoveryStatus, RemoteRecoveryStatus.published);
  });

  test('remoteSuccessLocalFinalizeFailureCanBeRecoveredWithoutNewMK', () async {
    final remote = FakeGithubBackupService()..failPasswordStateUpdateOnce = true;
    const password = 'BlockB!Password44';

    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: password,
        mnemonicWords: _mnemonic,
        remoteService: remote,
        repository: 'owner/repo',
      ),
      throwsA(isA<GithubSyncException>()),
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    final recordAfterFailure = await MasterKeyLocalStore.read();
    expect(recordAfterFailure!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(remote.files.containsKey('device_key.json'), isTrue);

    // Simulate process restart: the in-memory MK disappears, so reconciliation
    // must restore the same persisted local authority and never generate a new key.
    MasterKeyManager.instance.resetForTesting();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
      remoteService: remote,
      repository: 'owner/repo',
    );

    expect(MasterKeyManager.instance.state, MasterKeyState.authoritative);
    final retried = await MasterKeyLocalStore.read();
    expect(retried!.recoveryWrap, recordAfterFailure.recoveryWrap);
  });

  test('twoConcurrentFirstDeviceCallsShareOneAuthorityOperation', () async {
    final remote = FakeGithubBackupService();
    final first = MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
      remoteService: remote,
      repository: 'owner/repo',
    );
    final second = MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
      remoteService: remote,
      repository: 'owner/repo',
    );

    await Future.wait([first, second]);
    expect(MasterKeyManager.instance.state, MasterKeyState.authoritative);
    final record = await MasterKeyLocalStore.read();
    expect(record!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(remote.files.containsKey('device_key.json'), isTrue);
  });

  test('staleRemoteRefRejected', () async {
    final remote = FakeGithubBackupService();
    remote.seed('device_key.json', '{"v":1}');
    final stale = remote.branchSha;
    remote.seed('password_state.json', '{"passwordGeneration":1}');
    remote.branchSha = 'sha-moved';
    expect(remote.branchSha, isNot(stale));

    await expectLater(
      remote.updateFilesWithFastForwardCheck(
        updates: {'device_key.json': '{"v":2}'},
        message: 'stale test',
        expectedParentSha: stale,
      ),
      throwsA(isA<GithubConditionalWriteConflict>()),
    );
  });
}
