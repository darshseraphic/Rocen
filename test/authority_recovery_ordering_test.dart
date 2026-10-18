import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/password_key_derivation.dart';
import 'package:rocen/core/session_security_manager.dart';

import 'support/fake_github_remote.dart';

const _password = 'BlockB!Password44';
const _mnemonic = <String>[
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

void main() {
  late Directory tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_recovery_order_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });
  setUp(() async {
    SessionSecurityManager.instance.resetForTesting();
    MasterKeyManager.instance.resetForTesting();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
  });
  tearDown(() => SessionSecurityManager.instance.lockSync());
  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<String> makeWrapper() async {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    try {
      return await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
        masterKeyBytes: key,
        rawPassword: _password,
        mnemonicWords: _mnemonic,
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  for (final malformedState in <String>[
    '{"passwordGeneration":1,"passwordGeneration":1}',
    '{"passwordGeneration":1,"passwordChangeId":"x","passwordChangedAt":"2026-01-01T00:00:00Z","changedByDeviceId":"missing","devices":[]}',
  ]) {
    test('paired malformed password state rejects before first local write',
        () async {
      final remote = FakeGithubRemote()
        ..seed('device_key.json', await makeWrapper())
        ..seed('password_state.json', malformedState);
      final beforeHive = Hive.box(MasterKeyLocalStore.boxName).toMap();
      final beforeMutations = remote.mutationCount;

      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: remote.service,
          repository: 'owner/repo',
        ),
        throwsA(isA<Exception>()),
      );

      expect(await MasterKeyLocalStore.read(), isNull);
      expect(Hive.box(MasterKeyLocalStore.boxName).toMap(), beforeHive);
      expect(remote.mutationCount, beforeMutations);
      expect(remote.files['password_state.json'], malformedState);
    });
  }

  test('valid recovery with legitimately absent state initializes shared state',
      () async {
    final remote = FakeGithubRemote()
      ..seed('device_key.json', await makeWrapper());
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: _password,
      mnemonicWords: _mnemonic,
      remoteService: remote.service,
      repository: 'owner/repo',
    );
    expect(await MasterKeyLocalStore.read(), isNotNull);
    expect(remote.files.containsKey('password_state.json'), isTrue);
    expect(remote.mutationLog, isNotEmpty,
        reason: 'supported missing-state recovery creates shared state');
  });

  test('ownedLocal create race accepts only the exact attempted wrapper',
      () async {
    final FakeGithubRemote remote = FakeGithubRemote()
      ..raceWinnerUsesAttemptedContent = true;
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: _password,
      mnemonicWords: _mnemonic,
      remoteService: remote.service,
      repository: 'owner/repo',
    );
    final record = await MasterKeyLocalStore.read();
    expect(record, isNotNull);
    expect(record!.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(remote.files['device_key.json'], record.recoveryWrap);
    expect(remote.files.containsKey('password_state.json'), isTrue);
  });

  test(
      'ownedLocal create race records conflict for a different wrapper even '
      'when it unwraps to the same MK', () async {
    final FakeGithubRemote remote = FakeGithubRemote()
      ..raceWinnerContent = await makeWrapper();
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      ),
      throwsStateError,
    );
    final record = await MasterKeyLocalStore.read();
    expect(record, isNotNull);
    expect(record!.remoteRecoveryStatus, RemoteRecoveryStatus.conflict);
    expect(remote.files['device_key.json'], isNot(record.recoveryWrap));
    expect(remote.files.containsKey('password_state.json'), isFalse);
  });

  test(
      'malformed state appearing after wrapper create leaves marker unpublished',
      () async {
    final remote = FakeGithubRemote();
    remote.onContentsCreate = (path) {
      if (path == 'device_key.json') {
        remote.seed('password_state.json',
            '{"passwordGeneration":1,"passwordGeneration":2}');
      }
    };
    await expectLater(
      MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      ),
      throwsA(isA<Exception>()),
    );
    final record = await MasterKeyLocalStore.read();
    expect(record, isNotNull);
    expect(record!.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished);
    expect(Hive.box(MasterKeyLocalStore.boxName).get('device_id'), isNull);
    expect(remote.files.containsKey('device_key.json'), isTrue,
        reason:
            'the committed wrapper is not claimed to have been rolled back');
    expect(remote.files.containsKey('password_state.json'), isTrue);
    expect(remote.mutationCount, greaterThan(0));
  });
}
