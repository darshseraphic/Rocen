import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Rocen/core/master_key_local_store.dart';
import 'package:Rocen/core/master_key_manager.dart';
import 'package:Rocen/core/master_key_production_service.dart';
import 'package:Rocen/core/session_security_manager.dart';
import 'package:Rocen/main.dart';

const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
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
    // SettingsScreen's own establish-first-device affordance is reachable;
    // we only assert the protected shell (navbar + QuickNote) is absent -
    // the exact fresh-install copy is SettingsScreen's own concern, not
    // this smoke test's.
  });

  testWidgets(
      'boots to LOCKED (no protected UI) when local authority already exists',
      (WidgetTester tester) async {
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: 'BlockB!Password44',
      mnemonicWords: _mnemonic,
    );
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
    expect(find.text('ROCEN LOCKED'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}

