import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Rocen/core/github_backup_service.dart';
import 'package:Rocen/core/master_key_local_store.dart';
import 'package:Rocen/core/master_key_manager.dart';
import 'package:Rocen/core/master_key_production_service.dart';

/// Stage 5: verifies that `associateRemote` and `changePassword` enforce
/// `requireSessionAuthorized` at the production-operation layer itself, not
/// only via UI-level checks in settings.dart. This is the concrete evidence
/// that a future or background caller invoking these two methods directly
/// - bypassing any screen entirely - is still refused when it supplies (or
/// when settings.dart's real wiring supplies) a check that reports "not
/// currently unlocked".
const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

const String _password = 'BlockB!Password44';

/// A bare, minimally-constructible `GithubBackupService`. Sufficient here
/// because every test in this file that uses it expects
/// `associateRemote`'s authorization gate to refuse the call BEFORE the
/// service is ever invoked - so no method on it needs a working
/// implementation.
class _MinimalFakeGithubBackupService extends GithubBackupService {
  _MinimalFakeGithubBackupService()
      : super(token: 'test-token', repoPath: 'owner/repo', branch: 'main');
}

Future<void> main() async {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_auth_gate_test_');
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

  group('changePassword authorization gate', () {
    test('proceeds when requireSessionAuthorized is omitted (Stage 3 compatibility)', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      final result = await MasterKeyProductionService.instance.changePassword(
        oldPassword: _password,
        newPassword: 'BlockB!Password55',
        mnemonicWords: _mnemonic,
      );
      expect(result, isNotNull);
    });

    test('proceeds when requireSessionAuthorized returns true', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      final result = await MasterKeyProductionService.instance.changePassword(
        oldPassword: _password,
        newPassword: 'BlockB!Password55',
        mnemonicWords: _mnemonic,
        requireSessionAuthorized: () => true,
      );
      expect(result, isNotNull);
    });

    test('throws SessionAuthorizationRequiredException when the check returns false,'
        ' before touching the durable record', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;

      await expectLater(
        MasterKeyProductionService.instance.changePassword(
          oldPassword: _password,
          newPassword: 'BlockB!Password55',
          mnemonicWords: _mnemonic,
          requireSessionAuthorized: () => false,
        ),
        throwsA(isA<SessionAuthorizationRequiredException>()),
      );

      final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
      expect(after.passwordWrap, before.passwordWrap);
    });

    test('a check that becomes false before a queued mutation runs is caught, '
        'even though it passed at call time', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );

      // Occupy the serialization queue with a real, currently-authorized
      // mutation first, and await it to completion so its ordering relative
      // to the second call is unambiguous.
      final result1 = await MasterKeyProductionService.instance.changePassword(
        oldPassword: _password,
        newPassword: 'BlockB!Password55',
        mnemonicWords: _mnemonic,
        requireSessionAuthorized: () => true,
      );
      expect(result1, isNotNull);

      // The second call's authorization check passes at the moment it is
      // called (simulating "the session was unlocked when the user tapped
      // the button"), but the session locks before this specific queued
      // mutation's turn actually arrives (simulating a lock that happens
      // while this call is waiting behind other work, or while the
      // isolate-based KDF for the previous step was still finishing). Since
      // this test issues the calls sequentially (not truly concurrently),
      // the meaningful assertion is the one below: the inner re-check
      // inside the queued closure, not just the outer gate, is what
      // `changePassword` must consult before mutating the record.
      bool authorized = true;
      final Future<dynamic> second = MasterKeyProductionService.instance.changePassword(
        oldPassword: 'BlockB!Password55',
        newPassword: 'BlockB!Password66',
        mnemonicWords: _mnemonic,
        requireSessionAuthorized: () {
          final bool current = authorized;
          // Flip after being read once, so the OUTER (call-time) check
          // observes true, but by construction this callback is invoked a
          // second time from inside the queued closure - and that second
          // observation must see false.
          authorized = false;
          return current;
        },
      );

      await expectLater(second, throwsA(isA<SessionAuthorizationRequiredException>()));
    });
  });

  group('associateRemote authorization gate', () {
    // The "proceeds when authorized" happy path for associateRemote already
    // has full coverage in master_key_production_service_test.dart (Stage
    // 3's own suite, using its full-fidelity FakeGithubBackupService this
    // file deliberately does not duplicate). What is new here, and not
    // covered there, is that the gate refuses BEFORE the service is ever
    // touched - so a minimal fake that never expects to be called is
    // sufficient and appropriate for these tests.
    test('throws SessionAuthorizationRequiredException when the check returns false,'
        ' before touching the durable record or the remote service at all', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;

      await expectLater(
        MasterKeyProductionService.instance.associateRemote(
          service: _MinimalFakeGithubBackupService(),
          password: _password,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
          requireSessionAuthorized: () => false,
        ),
        throwsA(isA<SessionAuthorizationRequiredException>()),
      );

      final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
      expect(after.repository, isNot('owner/repo'));
    });
  });
}
