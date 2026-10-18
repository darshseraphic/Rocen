import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/activation_contract.dart';
import 'support/fake_github_remote.dart';

const List<String> _words = <String>[
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
const String _password = 'BlockB!Password44';
const int _max = PasswordStateManager.maxInt;

Map<String, dynamic> _state({
  required int generation,
  required int deviceNumber,
  required String deviceId,
}) =>
    <String, dynamic>{
      'passwordGeneration': generation,
      'passwordChangeId': 'change-1',
      'passwordChangedAt': '2026-01-01T00:00:00.000Z',
      'changedByDeviceId': deviceId,
      'devices': <Map<String, dynamic>>[
        <String, dynamic>{
          'deviceNumber': deviceNumber,
          'deviceId': deviceId,
          'passwordGeneration': generation,
        },
      ],
    };

Future<void> main() async {
  late Directory tempDir;
  final SessionSecurityManager ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_counter_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });
  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    ssm.finishBootstrap();
    enableSimulatedScreenAcknowledgementForTest();
  });
  tearDown(() => ssm.lockSync());
  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test(
      'device registration at maxInt refuses before local bookkeeping or '
      'remote mutation; maxInt-1 still permits the final valid number',
      () async {
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: _password,
      mnemonicWords: _words,
    );
    await ssm.unlock(
      password: _password,
      activateRoot: satisfyActivationContract,
      teardownRoot: () {},
    );
    final MasterKeyLocalRecord local = (await MasterKeyLocalStore.read())!;
    final FakeGithubRemote exhausted = FakeGithubRemote()
      ..seed('device_key.json', local.recoveryWrap)
      ..seed(
          'password_state.json',
          jsonEncode(_state(
            generation: 1,
            deviceNumber: _max,
            deviceId: 'device-other',
          )));
    final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;
    await expectLater(
      MasterKeyProductionService.instance.associateRemote(
        service: exhausted.service,
        password: _password,
        mnemonicWords: _words,
        repository: 'owner/repo',
        authorizationToken: ssm.captureAuthorization(),
      ),
      throwsA(isA<PasswordStateCounterExhaustedException>()),
    );
    expect((await MasterKeyLocalStore.read())!.isSamePersistedRecordAs(before),
        isTrue);
    expect(Hive.box(MasterKeyLocalStore.boxName).get('device_id'), isNull);
    expect(Hive.box(MasterKeyLocalStore.boxName).get('device_number'), isNull);
    expect(exhausted.mutationCount, 0);

    final FakeGithubRemote almost = FakeGithubRemote()
      ..seed('device_key.json', local.recoveryWrap)
      ..seed(
          'password_state.json',
          jsonEncode(_state(
            generation: 1,
            deviceNumber: _max - 1,
            deviceId: 'device-other',
          )));
    await MasterKeyProductionService.instance.associateRemote(
      service: almost.service,
      password: _password,
      mnemonicWords: _words,
      repository: 'owner/repo',
      authorizationToken: ssm.captureAuthorization(),
    );
    expect(almost.mutationCount, greaterThan(0));
    expect(Hive.box(MasterKeyLocalStore.boxName).get('device_number'), _max);
  }, timeout: const Timeout(Duration(minutes: 20)));

  test(
      'rotation at maxInt refuses with typed error and preserves the full '
      'local record and remote files', () async {
    final FakeGithubRemote remote = FakeGithubRemote();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: _password,
      mnemonicWords: _words,
      remoteService: remote.service,
      repository: 'owner/repo',
    );
    await ssm.unlock(
      password: _password,
      activateRoot: satisfyActivationContract,
      teardownRoot: () {},
    );
    final SessionAuthorizationToken token = ssm.captureAuthorization();
    await MasterKeyProductionService.instance.changePassword(
      oldPassword: _password,
      newPassword: 'NewBlockB!Password55',
      mnemonicWords: _words,
      authorizationToken: token,
    );
    final MasterKeyLocalRecord pending = (await MasterKeyLocalStore.read())!;
    remote.seed(
        'password_state.json',
        jsonEncode(_state(
          generation: _max,
          deviceNumber: 1,
          deviceId:
              Hive.box(MasterKeyLocalStore.boxName).get('device_id') as String,
        )));
    final Map<String, String> remoteBefore =
        Map<String, String>.from(remote.files);
    final int mutationCountBefore = remote.mutationCount;

    await expectLater(
      MasterKeyProductionService.instance.associateRemote(
        service: remote.service,
        password: 'NewBlockB!Password55',
        mnemonicWords: _words,
        repository: 'owner/repo',
        authorizationToken: token,
      ),
      throwsA(isA<PasswordStateCounterExhaustedException>()),
    );
    expect((await MasterKeyLocalStore.read())!.isSamePersistedRecordAs(pending),
        isTrue);
    expect(remote.files, remoteBefore);
    expect(remote.mutationCount, mutationCountBefore);
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('rotation immediately below maxInt emits a parser-accepted max value',
      () async {
    final FakeGithubRemote remote = FakeGithubRemote();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: _password,
      mnemonicWords: _words,
      remoteService: remote.service,
      repository: 'owner/repo',
    );
    await ssm.unlock(
      password: _password,
      activateRoot: satisfyActivationContract,
      teardownRoot: () {},
    );
    final SessionAuthorizationToken token = ssm.captureAuthorization();
    await MasterKeyProductionService.instance.changePassword(
      oldPassword: _password,
      newPassword: 'NewBlockB!Password55',
      mnemonicWords: _words,
      authorizationToken: token,
    );
    remote.seed(
      'password_state.json',
      jsonEncode(_state(
        generation: _max - 1,
        deviceNumber: 1,
        deviceId:
            Hive.box(MasterKeyLocalStore.boxName).get('device_id') as String,
      )),
    );
    await Hive.box(MasterKeyLocalStore.boxName)
        .put('known_password_generation', _max - 1);
    final int before = remote.mutationCount;
    await MasterKeyProductionService.instance.associateRemote(
      service: remote.service,
      password: 'NewBlockB!Password55',
      mnemonicWords: _words,
      repository: 'owner/repo',
      authorizationToken: token,
    );
    expect(remote.mutationCount, greaterThan(before));
    final Map<String, dynamic> emitted = jsonDecode(
      remote.files['password_state.json']!,
    ) as Map<String, dynamic>;
    expect(emitted['passwordGeneration'], _max);
    expect((emitted['devices'] as List<dynamic>).single['passwordGeneration'],
        _max);
    expect((await MasterKeyLocalStore.read())!.remoteRecoveryStatus,
        RemoteRecoveryStatus.published);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
