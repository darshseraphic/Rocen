import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'package:rocen/core/protected_session_resources.dart';
import 'package:rocen/features/lock_screen.dart';
import 'package:rocen/main.dart';
import 'support/activation_contract.dart';

/// The activation contract cannot be skipped by a caller-supplied callback.
///
/// Trust boundary (stated honestly): this hardens an internal API inside ONE
/// Dart process. A same-process caller that deliberately calls
/// `registerSessionResource` and `reportProtectedRootReady` itself satisfies
/// the contract; this is not a sandbox against hostile in-process code. What
/// it prevents is an absent or no-op activator silently producing UNLOCKED
/// and a SessionAuthorizationToken.
///
/// Needs the test-control define (resets):
///   flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true
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

Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_contract_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: _password,
      mnemonicWords: _mnemonic,
    );
    ssm.finishBootstrap();
  });

  tearDown(() => ssm.lockSync());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> expectRefused(
    Future<void> Function(ActivationCapability) activator,
    String why,
  ) async {
    await expectLater(
      ssm.unlock(
        password: _password,
        activateRoot: activator,
        teardownRoot: () {},
      ),
      throwsA(isA<SessionActivationException>()),
      reason: why,
    );
    expect(ssm.state, SessionState.locked, reason: why);
    expect(() => ssm.captureAuthorization(),
        throwsA(isA<SessionAuthorizationException>()),
        reason: '$why: no token was minted');
    expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse,
        reason: '$why: keys were destroyed by the rollback');
    expect(ssm.activationDiagnostics.registeredSessionResources, 0);
  }

  group('activation contract', () {
    test('a NO-OP activator cannot unlock or mint authorization', () async {
      await expectRefused((_) async {}, 'no-op activator');
    });

    test(
        'an activator that only registers a resource (no root-ready '
        'report) cannot unlock', () async {
      var invoked = false;
      await expectRefused((c) async {
        invoked = true;
        final resources = ProtectedSessionResources();
        ssm.registerSessionResource(c, resources);
      }, 'registered but not ready');
      expect(invoked, isFalse,
          reason:
              'unsupported screen policy blocks activation before callback');
    });

    test(
        'a root-ready report without a registered privileged resource is '
        'refused', () async {
      await expectRefused((c) async {
        expect(() => ssm.reportProtectedRootReady(c),
            throwsA(isA<SessionAuthorizationException>()));
      }, 'ready without resource');
    });

    test('unsupported host refuses activation before invoking the root',
        () async {
      var invoked = false;
      await expectRefused((capability) async {
        invoked = true;
        await satisfyActivationContract(capability);
      }, 'unsupported platform');
      expect(invoked, isFalse,
          reason: 'capture policy is applied before root construction');
    });

    test(
        'the manager - not the activator callback - owns screen-capture '
        'policy (SOURCE-REVIEWED ONLY)', () {
      final String mgr = File(
              '${Directory.current.path}/lib/core/session_security_manager.dart')
          .readAsStringSync();
      expect(mgr, contains('await ScreenSecurity.acquire()'));
      expect(mgr, contains('ScreenSecurity.satisfiesPolicy(screenStatus)'));
      final String res = File(
              '${Directory.current.path}/lib/core/protected_session_resources.dart')
          .readAsStringSync();
      expect(res, isNot(contains('ScreenSecurity')),
          reason: 'the callback side no longer applies the policy');
      // Order inside unlock(): policy, then activateRoot, then contract
      // check, then the commit that mints the token.
      final int policy =
          mgr.indexOf('ScreenSecurity.satisfiesPolicy(screenStatus)');
      final int activate = mgr.indexOf('await activateRoot(capability)');
      final int contract =
          mgr.indexOf('!_activatorResourceRegistered || !_rootReady');
      final int commit =
          mgr.indexOf('_authorization = SessionAuthorizationToken._(_epoch);');
      expect(policy, lessThan(activate));
      expect(activate, lessThan(contract));
      expect(contract, lessThan(commit));
    });
  });

  testWidgets(
      'main.dart shows failure and stays locked on an unsupported platform',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RocenApp()));
    await tester.pumpAndSettle();
    // The public shell launches first; the unlock form is the SET tab content.
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey<String>('rocen-public-navbar')),
      matching: find.text('SET'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _password);
    await tester.tap(find.text('UNLOCK'));
    await tester.runAsync(() async {
      for (int i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(ssm.state, SessionState.locked);
    expect(ssm.activationDiagnostics.registeredSessionResources, 0);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(
      find.text(
          'Screen-capture protection could not be enabled, so the session was not opened.'),
      findsOneWidget,
    );
  });
}
