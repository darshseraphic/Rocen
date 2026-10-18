import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'package:rocen/features/lock_screen.dart';
import 'package:rocen/main.dart';
import 'support/activation_contract.dart';

const List<String> _mnemonic = <String>[
  'abandon',
  'ability',
  'able',
  'about',
  'above',
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
    tempDir = await Directory.systemTemp.createTemp('rocen_shell_session_');
    Hive.init(tempDir.path);
    await Hive.openBox('rocen_settings_box');
  });

  setUp(() async {
    SessionSecurityManager.instance.resetForTesting();
    MasterKeyManager.instance.resetForTesting();
    await Hive.box('rocen_settings_box').clear();
    enableSimulatedScreenAcknowledgementForTest();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );
    SessionSecurityManager.instance.finishBootstrap();
  });

  tearDown(() {
    SecurityCheckpoints.reset();
    SessionSecurityManager.instance.lockSync();
    MasterKeyManager.instance.resetForTesting();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Finder publicTab(String label) => find.descendant(
        of: find.byKey(const ValueKey<String>('rocen-public-navbar')),
        matching: find.text(label),
      );

  /// Alternates real-time slices (isolate/KDF work, Hive) with fake-clock
  /// pumps (timers and continuations in the widget test's zone). A zero-length
  /// pump never advances fake timers, so it must not be used to wait.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    int maxSlices = 1200,
  }) async {
    for (int i = 0; i < maxSlices && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openRocen(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RocenApp()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(publicTab('SET'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('rocen-protected-app')),
        findsNothing);
  }

  Future<void> submitPassword(WidgetTester tester) async {
    await tester.tap(publicTab('SET'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LockScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'BlockB!Password44');
    await tester.tap(find.text('UNLOCK'));
  }

  Future<void> unlockViaUi(WidgetTester tester) async {
    await submitPassword(tester);
    await pumpUntil(tester,
        () => SessionSecurityManager.instance.state == SessionState.unlocked);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder get protectedApp =>
      find.byKey(const ValueKey<String>('rocen-protected-app'));

  void expectLockedAndClean() {
    final SessionSecurityManager ssm = SessionSecurityManager.instance;
    expect(ssm.state, SessionState.locked);
    expect(ssm.activationDiagnostics.registeredSessionResources, 0,
        reason: 'resources are synchronously destroyed by the manager lock');
    expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    expect(() => ssm.captureAuthorization(),
        throwsA(isA<SessionAuthorizationException>()));
  }

  testWidgets(
    'successful activation uses protected app; lock returns to selected public preview',
    (WidgetTester tester) async {
      await openRocen(tester);
      expect(
          () => SessionSecurityManager.instance.captureAuthorization(),
          throwsA(isA<SessionAuthorizationException>()),
          reason: 'no authorization token exists before unlock');

      await unlockViaUi(tester);

      expect(SessionSecurityManager.instance.state, SessionState.unlocked);
      expect(protectedApp, findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('rocen-shell-app')), findsNothing);
      expect(SessionSecurityManager.instance.captureAuthorization(),
          isA<SessionAuthorizationToken>());

      await tester.tap(find.text('CLIP').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('CLIPBOARD'), findsOneWidget);

      SessionSecurityManager.instance.lockSync();
      expectLockedAndClean();
      await tester.pumpAndSettle();

      expect(protectedApp, findsNothing);
      expect(find.byKey(const ValueKey<String>('rocen-shell-app')),
          findsOneWidget);
      expect(find.text('PUBLIC PREVIEW'), findsOneWidget);
      expect(publicTab('CLIP'), findsOneWidget,
          reason: 'the non-sensitive destination survives the lock');
      expect(find.text('CLIPBOARD'), findsNothing);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'repeated lock/unlock cycles leave one navigator and no leaked resources',
    (WidgetTester tester) async {
      await openRocen(tester);
      for (int cycle = 0; cycle < 2; cycle++) {
        await unlockViaUi(tester);
        expect(SessionSecurityManager.instance.state, SessionState.unlocked,
            reason: 'cycle $cycle');
        expect(protectedApp, findsOneWidget, reason: 'cycle $cycle');
        expect(find.byType(ProtectedSessionApp), findsOneWidget);
        expect(find.byType(MaterialApp), findsOneWidget,
            reason: 'exactly one app/Navigator tree (protected) is mounted');
        expect(
            SessionSecurityManager
                .instance.activationDiagnostics.registeredSessionResources,
            1,
            reason: 'one session-owned resource while unlocked');

        await tester.tap(find.text('NOTE').last);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('TODO').last);
        await tester.pump(const Duration(milliseconds: 100));

        SessionSecurityManager.instance.lockSync();
        expectLockedAndClean();
        await tester.pumpAndSettle();
        expect(protectedApp, findsNothing, reason: 'cycle $cycle');
        expect(find.byType(ProtectedSessionApp), findsNothing);
        expect(find.byType(MaterialApp), findsOneWidget,
            reason: 'only the public shell remains after lock');
        expect(publicTab('SET'), findsOneWidget);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'stale activation cannot remount the protected app or unlock after lock',
    (WidgetTester tester) async {
      await openRocen(tester);

      SecurityCheckpoints.arm(SecurityCheckpoint.beforeActivationCommit);
      bool paused = false;
      unawaited(SecurityCheckpoints.waitUntilPaused(
              SecurityCheckpoint.beforeActivationCommit)
          .then((_) => paused = true));
      await submitPassword(tester);
      await pumpUntil(tester, () => paused);
      expect(paused, isTrue,
          reason: 'production activation reached the commit checkpoint');
      expect(SessionSecurityManager.instance.state, SessionState.activating);

      SessionSecurityManager.instance.lockSync();
      expectLockedAndClean();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeActivationCommit);

      // Let the stale activation observe the lock and unwind.
      for (int i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      expectLockedAndClean();
      expect(protectedApp, findsNothing,
          reason: 'a stale activation must not remount the protected app');
      expect(find.byType(ProtectedSessionApp), findsNothing);
      expect(find.byKey(const ValueKey<String>('rocen-shell-app')),
          findsOneWidget);
      expect(publicTab('SET'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
