import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'package:rocen/core/screen_security.dart';
import 'package:rocen/main.dart';

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

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_widget_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('rocen_settings_box');
  });

  setUp(() async {
    SessionSecurityManager.instance.resetForTesting();
    MasterKeyManager.instance.resetForTesting();
    await Hive.box('rocen_settings_box').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// The public shell (navbar + previews) is what launches; the account
  /// surface (setup, unlock, or the fail-closed account error) is the content
  /// of the SET tab inside that shell.
  Future<void> openSet(WidgetTester tester) async {
    expect(find.byKey(const ValueKey<String>('rocen-public-navbar')),
        findsOneWidget,
        reason: 'the public navbar is visible at launch');
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey<String>('rocen-public-navbar')),
      matching: find.text('SET'),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'boots to the unauthenticated setup shell when no local authority exists',
      (WidgetTester tester) async {
    // Stage 5: with no local Master Key authority record yet (fresh
    // install), the app must route to the existing, unauthenticated
    // first-device setup surface - never to a protected feature screen and
    // never to the ordinary password lock screen (there is no password to
    // check yet).
    await tester.pumpWidget(
      const ProviderScope(
        child: RocenApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QUICK NOTES'), findsNothing);
    await openSet(tester);
    expect(find.text('SET UP ROCEN'), findsOneWidget);
    expect(find.text('ROCEN LOCKED'), findsNothing,
        reason: 'no password exists yet, so there is nothing to unlock');
    // SettingsScreen's own establish-first-device affordance is reachable;
    // we only assert the protected shell (navbar + QuickNote) is absent -
    // the exact fresh-install copy is SettingsScreen's own concern, not
    // this smoke test's.
  });

  testWidgets(
      'boots to LOCKED (no protected UI) when local authority already exists',
      (WidgetTester tester) async {
    await tester.runAsync(
        () => MasterKeyProductionService.instance.establishFirstDevice(
              password: 'BlockB!Password44',
              mnemonicWords: _mnemonic,
            ));
    // Simulate a fresh process start: MasterKeyManager has no in-memory
    // authority yet, even though the local record is durable.
    MasterKeyManager.instance.resetForTesting();

    await tester.pumpWidget(
      const ProviderScope(
        child: RocenApp(),
      ),
    );
    await tester.pumpAndSettle();

    // No protected feature screen may be visible before unlock.
    expect(find.text('QUICK NOTES'), findsNothing);
    await openSet(tester);
    expect(find.text('ROCEN LOCKED'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
      'boots to the fail-closed corrupt-authority screen when a local record '
      'exists but cannot be read - never to setup, never to the lock screen',
      (WidgetTester tester) async {
    // This case tests the shell's corrupt-record routing, not KDF behavior.
    // Persist a malformed schema-1-shaped JSON string directly so the widget
    // test does not block on native KDF work inside its lifecycle harness.
    final box = Hive.box('rocen_settings_box');
    await tester.runAsync(() => box.put(
          'master_key_record_v1',
          jsonEncode(<String, Object>{
            'schema': 1,
            'revision': 1,
            'authority': 'authoritative',
          }),
        ));

    await tester.pumpWidget(
      const ProviderScope(
        child: RocenApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QUICK NOTES'), findsNothing);
    await openSet(tester);
    expect(find.text('ROCEN LOCKED'), findsNothing);
    expect(find.text('SET UP ROCEN'), findsNothing,
        reason: 'corrupt authority is never treated as a fresh install');
    expect(find.textContaining('COULD NOT READ YOUR ACCOUNT'), findsOneWidget);
  });

  testWidgets(
      'session boundary: unlock mounts a session-scoped MaterialApp with its '
      'own root container; lockSync() destroys the container synchronously, '
      'before any frame, and the next frame removes the protected app',
      (WidgetTester tester) async {
    // Evidence: NOT executed in the authoring environment (no Flutter).
    const String pw = 'BlockB!Password44';
    await tester.runAsync(() async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: pw,
        mnemonicWords: _mnemonic,
      );
    });
    MasterKeyManager.instance.resetForTesting();

    await tester.pumpWidget(const ProviderScope(child: RocenApp()));
    await tester.pumpAndSettle();
    await openSet(tester);
    expect(find.text('ROCEN LOCKED'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('rocen-protected-app')),
        findsNothing);

    // Keep the production default-deny policy on unsupported/unavailable
    // hosts. This widget test exercises the real lock-screen flow there and
    // only runs the success branch when the platform integration acknowledges
    // protection; that acknowledgement is not native enforcement evidence.
    final ScreenSecurityStatus captureStatus = await ScreenSecurity.acquire();
    ScreenSecurity.release();
    if (!ScreenSecurity.satisfiesPolicy(captureStatus)) {
      await tester.enterText(find.byType(TextField), pw);
      await tester.tap(find.text('UNLOCK'));
      await tester.runAsync(() async {
        for (int i = 0;
            i < 200 &&
                SessionSecurityManager.instance.state ==
                    SessionState.unlocking;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(SessionSecurityManager.instance.state, SessionState.locked);
      expect(find.byKey(const ValueKey<String>('rocen-protected-app')),
          findsNothing);
      expect(() => SessionSecurityManager.instance.captureAuthorization(),
          throwsA(isA<SessionAuthorizationException>()));
      return;
    }

    await tester.enterText(find.byType(TextField), pw);
    await tester.tap(find.text('UNLOCK'));
    // Real Argon2id work runs outside the fake-async zone.
    await tester.runAsync(() async {
      for (int i = 0;
          i < 200 &&
              SessionSecurityManager.instance.state != SessionState.unlocked;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(SessionSecurityManager.instance.state, SessionState.unlocked);
    expect(find.byKey(const ValueKey<String>('rocen-protected-app')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('rocen-shell-app')), findsNothing,
        reason: 'the shell MaterialApp/Navigator is not built while a '
            'session exists');
    expect(find.text('ROCEN LOCKED'), findsNothing);
    expect(
        SessionSecurityManager
            .instance.activationDiagnostics.registeredSessionResources,
        1);

    SessionSecurityManager.instance.lockSync();
    // Synchronous destruction: no frame has been pumped yet.
    expect(
        SessionSecurityManager
            .instance.activationDiagnostics.registeredSessionResources,
        0);
    expect(SessionSecurityManager.instance.state, SessionState.locked);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('rocen-protected-app')),
        findsNothing);
    expect(find.text('ROCEN LOCKED'), findsOneWidget);
  });
}
