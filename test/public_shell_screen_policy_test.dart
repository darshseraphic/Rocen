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

/// Default-deny screen-capture policy through the PUBLIC shell.
///
/// This file deliberately never installs the simulated screen
/// acknowledgement (`enableSimulatedScreenAcknowledgementForTest`). On a
/// non-Android test host the production policy therefore reports
/// "unsupported platform", which must fail closed. These results say nothing
/// about Android OS enforcement; they show that the Dart policy refuses to
/// proceed without an acknowledgement.
const List<String> _mnemonic = <String>[
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
    tempDir = await Directory.systemTemp.createTemp('rocen_screen_policy_');
    Hive.init(tempDir.path);
    await Hive.openBox('rocen_settings_box');
  });

  setUp(() async {
    SessionSecurityManager.instance.resetForTesting();
    MasterKeyManager.instance.resetForTesting();
    await Hive.box('rocen_settings_box').clear();
  });

  tearDown(() async {
    SessionSecurityManager.instance.lockSync();
    MasterKeyManager.instance.resetForTesting();
    await Hive.box('rocen_settings_box').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Finder publicTab(String label) => find.descendant(
        of: find.byKey(const ValueKey<String>('rocen-public-navbar')),
        matching: find.text(label),
      );

  Future<void> pumpUntil(WidgetTester tester, bool Function() done,
      {int maxSlices = 1200}) async {
    for (int i = 0; i < maxSlices && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'setup refuses to start when screen protection is not acknowledged: no '
    'account, no recovery phrase',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: RocenApp()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(publicTab('SET'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CREATE LOCAL-ONLY ACCOUNT'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'P4ssword2-Normal!');
      await tester.pump();
      await tester.tap(find.text('CONFIRM').last);
      await tester.pumpAndSettle();
      expect(find.text('ARE YOU SURE YOU WANT TO SET THIS PASSWORD?'),
          findsOneWidget);
      await tester.tap(find.text('CONFIRM').last);
      await pumpUntil(tester,
          () => find.text('SCREEN PROTECTION UNAVAILABLE').evaluate().isNotEmpty);

      expect(find.text('SCREEN PROTECTION UNAVAILABLE'), findsOneWidget);
      expect(find.text('RECOVERY PHRASE'), findsNothing,
          reason: 'the phrase is never shown without acknowledged protection');
      expect(Hive.box('rocen_settings_box').get('master_key_record_v1'), isNull,
          reason: 'no authority is created when protection is unavailable');
      expect(publicTab('NOTE'), findsOneWidget,
          reason: 'the public navbar stays available');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'unlock with unavailable screen protection leaves the user locked in a '
    'usable public shell',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        await MasterKeyProductionService.instance.establishFirstDevice(
          password: 'BlockB!Password44',
          mnemonicWords: _mnemonic,
        );
      });
      MasterKeyManager.instance.resetForTesting();

      await tester.pumpWidget(const ProviderScope(child: RocenApp()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(publicTab('SET'));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'BlockB!Password44');
      await tester.tap(find.text('UNLOCK'));
      await pumpUntil(
          tester,
          () => find
              .textContaining('Screen-capture protection could not be enabled')
              .evaluate()
              .isNotEmpty);

      expect(
          find.textContaining('Screen-capture protection could not be enabled'),
          findsOneWidget);
      final SessionSecurityManager ssm = SessionSecurityManager.instance;
      expect(ssm.state, SessionState.locked);
      expect(find.byKey(const ValueKey<String>('rocen-protected-app')),
          findsNothing);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      expect(ssm.activationDiagnostics.registeredSessionResources, 0);
      expect(() => ssm.captureAuthorization(),
          throwsA(isA<SessionAuthorizationException>()));

      // The public shell remains usable after the failed activation.
      for (final String tab in <String>['NOTE', 'CLIP', 'TODO', 'YEAR']) {
        await tester.tap(publicTab(tab));
        await tester.pumpAndSettle();
        expect(find.text('PUBLIC PREVIEW'), findsOneWidget, reason: tab);
      }
      expect(ssm.state, SessionState.locked);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
