import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/github_backup_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/fake_github_remote.dart';
import 'support/activation_contract.dart';

/// Strict schema of the REMOTE password_state.json. Malformed authority
/// metadata must be refused before any remote mutation and before any local
/// password-state bookkeeping. Needs the test-control define (resets):
///   flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true
///
/// Evidence: NOT executed in the authoring environment (no Dart/Flutter).
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
const String _password = 'BlockB!Password44';

Map<String, dynamic> _valid() => <String, dynamic>{
      'passwordGeneration': 1,
      'passwordChangeId': 'change-1',
      'passwordChangedAt': '2026-01-01T00:00:00.000Z',
      'changedByDeviceId': 'device-other',
      'devices': <dynamic>[
        <String, dynamic>{
          'deviceNumber': 1,
          'deviceId': 'device-other',
          'passwordGeneration': 1,
        },
      ],
    };

Map<String, dynamic> _dev(Map<String, dynamic> s, [int i = 0]) =>
    (s['devices'] as List<dynamic>)[i] as Map<String, dynamic>;

Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_pstate_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    enableSimulatedScreenAcknowledgementForTest();
  });

  tearDown(() => ssm.lockSync());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Object? psKey(String k) => Hive.box(MasterKeyLocalStore.boxName).get(k);

  group('remote password_state.json is parsed STRICTLY', () {
    final Map<String, void Function(Map<String, dynamic>)> bad =
        <String, void Function(Map<String, dynamic>)>{
      'generation as string': (s) => s['passwordGeneration'] = '1',
      'generation as double': (s) => s['passwordGeneration'] = 1.0,
      'generation as bool': (s) => s['passwordGeneration'] = true,
      'generation null': (s) => s['passwordGeneration'] = null,
      'generation 0': (s) => s['passwordGeneration'] = 0,
      'generation negative': (s) => s['passwordGeneration'] = -3,
      'generation too large': (s) => s['passwordGeneration'] = 2147483648,
      'changeId not string': (s) => s['passwordChangeId'] = 5,
      'changeId empty': (s) => s['passwordChangeId'] = '',
      'changeId padded left': (s) => s['passwordChangeId'] = ' change-1',
      'changeId padded right': (s) => s['passwordChangeId'] = 'change-1 ',
      'changeId null': (s) => s['passwordChangeId'] = null,
      'changedAt not string': (s) => s['passwordChangedAt'] = 20260101,
      'changedAt empty': (s) => s['passwordChangedAt'] = '',
      'changedAt padded': (s) => s['passwordChangedAt'] = ' 2026-01-01 ',
      'changedBy not string': (s) => s['changedByDeviceId'] = 7,
      'changedBy empty': (s) => s['changedByDeviceId'] = '',
      'changedBy padded': (s) => s['changedByDeviceId'] = 'device-other ',
      'changedBy not registered': (s) => s['changedByDeviceId'] = 'device-zzz',
      'missing passwordGeneration': (s) => s.remove('passwordGeneration'),
      'missing passwordChangeId': (s) => s.remove('passwordChangeId'),
      'missing passwordChangedAt': (s) => s.remove('passwordChangedAt'),
      'missing changedByDeviceId': (s) => s.remove('changedByDeviceId'),
      'missing devices': (s) => s.remove('devices'),
      'extra top-level field': (s) => s['extra'] = 1,
      'devices not a list': (s) => s['devices'] = <String, dynamic>{},
      'devices empty': (s) => s['devices'] = <dynamic>[],
      'device not an object': (s) => s['devices'] = <dynamic>['x'],
      'device missing key': (s) => _dev(s).remove('deviceId'),
      'device extra key': (s) => _dev(s)['extra'] = true,
      'deviceNumber as string': (s) => _dev(s)['deviceNumber'] = '1',
      'deviceNumber as double': (s) => _dev(s)['deviceNumber'] = 1.0,
      'deviceNumber as bool': (s) => _dev(s)['deviceNumber'] = true,
      'deviceNumber null': (s) => _dev(s)['deviceNumber'] = null,
      'deviceNumber 0': (s) => _dev(s)['deviceNumber'] = 0,
      'deviceId not string': (s) => _dev(s)['deviceId'] = 5,
      'deviceId empty': (s) => _dev(s)['deviceId'] = '',
      'deviceId padded': (s) => _dev(s)['deviceId'] = ' device-other',
      'deviceId null': (s) => _dev(s)['deviceId'] = null,
      'device generation as string': (s) => _dev(s)['passwordGeneration'] = '1',
      'device generation double': (s) => _dev(s)['passwordGeneration'] = 1.0,
      'device generation above top-level': (s) =>
          _dev(s)['passwordGeneration'] = 2,
      'duplicate deviceId': (s) => (s['devices'] as List<dynamic>)
              .add(<String, dynamic>{
            'deviceNumber': 2,
            'deviceId': 'device-other',
            'passwordGeneration': 1
          }),
      'duplicate deviceNumber': (s) => (s['devices'] as List<dynamic>)
              .add(<String, dynamic>{
            'deviceNumber': 1,
            'deviceId': 'device-second',
            'passwordGeneration': 1
          }),
    };

    test(
        'every malformed state is refused with ZERO mutating requests and '
        'NO password-state bookkeeping; a valid state still registers the '
        'device', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      final local = (await MasterKeyLocalStore.read())!;
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final token = ssm.captureAuthorization();

      for (final MapEntry<String, void Function(Map<String, dynamic>)> c
          in bad.entries) {
        final Map<String, dynamic> state = _valid();
        c.value(state);
        final remote = FakeGithubRemote()
          ..seed('device_key.json', local.recoveryWrap)
          ..seed('password_state.json', jsonEncode(state));
        await expectLater(
          MasterKeyProductionService.instance.associateRemote(
            service: remote.service,
            password: _password,
            mnemonicWords: _mnemonic,
            repository: 'owner/repo',
            authorizationToken: token,
          ),
          throwsA(isA<FormatException>()),
          reason: c.key,
        );
        expect(
            (await MasterKeyLocalStore.read())!.isSamePersistedRecordAs(local),
            isTrue,
            reason: '${c.key}: entire local authority record');
        expect(remote.mutationCount, 0, reason: '${c.key}: remote mutation');
        expect(psKey('device_id'), isNull, reason: '${c.key}: device id');
        expect(psKey('device_number'), isNull, reason: '${c.key}: number');
        expect(psKey('known_password_generation'), isNull,
            reason: '${c.key}: generation');
      }

      // Control: the valid current-schema state is accepted and the device
      // registers (a mutation happens, bookkeeping is recorded).
      final good = FakeGithubRemote()
        ..seed('device_key.json', local.recoveryWrap)
        ..seed('password_state.json', jsonEncode(_valid()));
      await MasterKeyProductionService.instance.associateRemote(
        service: good.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
        authorizationToken: token,
      );
      expect(good.mutationCount, greaterThan(0));
      expect(psKey('known_password_generation'), 1);
      expect(psKey('device_number'), 2);
      expect(good.files['password_state.json'], contains('"deviceNumber":2'));
    }, timeout: const Timeout(Duration(minutes: 20)));

    test('the parser source has no coercion (SOURCE-REVIEWED ONLY)', () {
      final String src =
          File('${Directory.current.path}/lib/core/password_state_manager.dart')
              .readAsStringSync();
      final String parser = src.substring(
          src.indexOf('static _ParsedPasswordState _parseState('),
          src.indexOf('static int _nextDeviceNumber('));
      expect(parser, isNot(contains('tryParse')));
      expect(parser, isNot(contains('toString()')));
      expect(parser, isNot(contains('.trim()')),
          reason: 'values are compared with their trim, never replaced by it');
      expect(src, isNot(contains('_decodeDevices')));
    });

    test(
        'duplicate raw authority properties refuse before local authority or '
        'device bookkeeping changes', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final MasterKeyLocalRecord local = (await MasterKeyLocalStore.read())!;
      final SessionAuthorizationToken token = ssm.captureAuthorization();
      final List<(String, String)> duplicateFixtures = <(String, String)>[
        ('device_key.json', '{"wrap":"a","wrap":"b"}'),
        ('device_key.json', '{"nested":{"id":1,"id":2}}'),
        ('device_key.json', '{"a":1,"\\u0061":2}'),
        (
          'password_state.json',
          '{"passwordGeneration":1,"passwordGeneration":1}'
        ),
        (
          'password_state.json',
          '{"devices":[{"deviceNumber":1,"deviceNumber":1}]}'
        ),
        ('password_state.json', '{"devices":[{"a":1,"\\u0061":2}]}'),
      ];
      for (final (String fileName, String raw) in duplicateFixtures) {
        final FakeGithubRemote remote = FakeGithubRemote();
        remote.seed('device_key.json',
            fileName == 'device_key.json' ? raw : local.recoveryWrap);
        remote.seed('password_state.json',
            fileName == 'password_state.json' ? raw : jsonEncode(_valid()));
        final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;
        final Map<String, dynamic> bookkeepingBefore = <String, dynamic>{
          for (final String key in <String>[
            'device_id',
            'device_number',
            'known_password_generation',
            'device_registered_at',
          ])
            key: psKey(key),
        };
        await expectLater(
          MasterKeyProductionService.instance.associateRemote(
            service: remote.service,
            password: _password,
            mnemonicWords: _mnemonic,
            repository: 'owner/repo',
            authorizationToken: token,
          ),
          throwsA(isA<GithubSyncException>()),
          reason: '$fileName: $raw',
        );
        expect(
            (await MasterKeyLocalStore.read())!.isSamePersistedRecordAs(before),
            isTrue);
        expect(<String, dynamic>{
          for (final String key in bookkeepingBefore.keys) key: psKey(key),
        }, bookkeepingBefore);
        expect(remote.mutationCount, 0);
      }
    }, timeout: const Timeout(Duration(minutes: 20)));
  });
}
