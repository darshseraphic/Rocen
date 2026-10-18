import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/database.dart';
import 'package:rocen/core/crypto_engine.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'package:rocen/features/lock_screen.dart';
import 'package:rocen/features/settings.dart';
import 'package:rocen/main.dart';
import 'package:rocen/navbar.dart';
import 'support/activation_contract.dart';

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

/// Counts dart:io HttpClient creations. Any GitHub/OAuth/token/repository
/// request made through dart:io would create one, so a count of zero shows
/// that the exercised public flow started no network client at all.
class _NetworkProbe extends HttpOverrides {
  int clientsCreated = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientsCreated++;
    return super.createHttpClient(context);
  }
}

void main() {
  late Directory tempDir;
  late _NetworkProbe networkProbe;
  HttpOverrides? previousHttpOverrides;
  late ProviderContainer publicContainer;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_public_shell_');
    Hive.init(tempDir.path);
    await Hive.openBox('rocen_settings_box');
    // Simulates only the Dart channel acknowledgement (not OS enforcement) so
    // the setup flow's default-deny screen-protection gate can pass on a test
    // host. Allowed only in security-test-control builds; set once per file
    // because it cannot change while a hold exists.
    enableSimulatedScreenAcknowledgementForTest();
  });

  setUp(() async {
    SessionSecurityManager.instance.resetForTesting();
    MasterKeyManager.instance.resetForTesting();
    await Hive.box('rocen_settings_box').clear();
    publicContainer = ProviderContainer();
    networkProbe = _NetworkProbe();
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = networkProbe;
  });

  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    publicContainer.dispose();
    SessionSecurityManager.instance.lockSync();
    MasterKeyManager.instance.resetForTesting();
    await Hive.box('rocen_settings_box').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpRocen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: publicContainer,
        child: const RocenApp(),
      ),
    );
  }

  Finder publicTab(String label) => find.descendant(
        of: find.byKey(const ValueKey<String>('rocen-public-navbar')),
        matching: find.text(label),
      );

  testWidgets('fresh launch immediately shows all five public tabs',
      (WidgetTester tester) async {
    await pumpRocen(tester);

    expect(publicTab('NOTE'), findsOneWidget);
    expect(publicTab('CLIP'), findsOneWidget);
    expect(publicTab('TODO'), findsOneWidget);
    expect(publicTab('YEAR'), findsOneWidget);
    expect(publicTab('SET'), findsOneWidget);
    expect(find.text('PUBLIC PREVIEW'), findsOneWidget);
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(publicContainer.exists(localDatabaseProvider), isFalse);
    expect(Hive.box('rocen_settings_box').get('master_key_record_v1'), isNull);
  });

  testWidgets('all public feature tabs are selectable safe previews',
      (WidgetTester tester) async {
    await pumpRocen(tester);
    await tester.pumpAndSettle();

    for (final (String tab, String heading) in <(String, String)>[
      ('NOTE', 'NOTES'),
      ('CLIP', 'CLIP'),
      ('TODO', 'TODO'),
      ('YEAR', 'YEAR'),
    ]) {
      await tester.tap(publicTab(tab));
      await tester.pumpAndSettle();
      expect(find.text(heading), findsAtLeastNWidgets(1),
          reason: '$tab preview');
      expect(find.text('PUBLIC PREVIEW'), findsOneWidget);
      expect(find.textContaining('does not read or save private content'),
          findsOneWidget);
      expect(publicContainer.exists(localDatabaseProvider), isFalse,
          reason: '$tab must not instantiate protected storage providers');
      expect(publicContainer.exists(navigationProvider), isFalse,
          reason: '$tab must not borrow protected navigation state');
    }
  });

  testWidgets('SET on a fresh install exposes explicit local-only setup',
      (WidgetTester tester) async {
    await pumpRocen(tester);
    await tester.pumpAndSettle();
    await tester.tap(publicTab('SET'));
    await tester.pumpAndSettle();

    expect(find.text('SET UP ROCEN'), findsOneWidget);
    expect(find.text('CREATE LOCAL-ONLY ACCOUNT'), findsOneWidget);
    expect(find.textContaining('does not contact GitHub'), findsOneWidget);
    expect(find.textContaining('not enabled by this account setup'),
        findsOneWidget);
    expect(find.text('SYSTEM SETTINGS'), findsNothing,
        reason: 'public setup must not build protected Settings controls');
    expect(publicTab('NOTE'), findsOneWidget,
        reason: 'SET is content within the persistent public shell');
    expect(Hive.box('rocen_settings_box').get('github_repo'), isNull);
    expect(Hive.box('rocen_settings_box').get('github_token'), isNull);

    await tester.tap(find.text('CREATE LOCAL-ONLY ACCOUNT'));
    await tester.pumpAndSettle();
    expect(find.text('SETUP CRYPTOGRAPHY PASSWORD'), findsOneWidget,
        reason: 'the existing first-device setup flow is reused');
    expect(Hive.box('rocen_settings_box').get('github_repo'), isNull);
    expect(Hive.box('rocen_settings_box').get('github_token'), isNull);
  });

  testWidgets(
      'local-only first-device setup writes local authority without GitHub state',
      (WidgetTester tester) async {
    await pumpRocen(tester);
    await tester.pumpAndSettle();
    await tester.tap(publicTab('SET'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREATE LOCAL-ONLY ACCOUNT'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'P4ssword2-Normal!');
    expect(CryptoEngine.isPasswordComplexityValid('P4ssword2-Normal!'), isTrue);
    await tester.pump();
    await tester.tap(find.text('CONFIRM').last);
    await tester.pumpAndSettle();
    expect(find.text('ARE YOU SURE YOU WANT TO SET THIS PASSWORD?'),
        findsOneWidget);

    await tester.tap(find.text('CONFIRM').last);
    // KDF work completes on an isolate, while its UI continuation and Hive
    // write return to the widget test's fake-async zone. Yield to real time
    // in short slices and pump the fake zone between slices. Wait for the
    // END of the flow (the recovery-phrase dialog), not only for the record:
    // the dialog is shown by a continuation that runs after the record write.
    for (int i = 0; i < 3000 && find.text('RECOVERY PHRASE').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('RECOVERY PHRASE'), findsOneWidget,
        reason: 'the existing recovery phrase display remains');
    expect(
        Hive.box('rocen_settings_box').get('master_key_record_v1'), isNotNull,
        reason: 'the existing first-device authority flow completed');
    expect(Hive.box('rocen_settings_box').get('github_repo'), isNull);
    expect(Hive.box('rocen_settings_box').get('github_token'), isNull);
    expect(networkProbe.clientsCreated, 0,
        reason: 'local-only setup must start no GitHub/OAuth/token/remote '
            'repository operation');
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('existing local authority routes SET to unlock, not setup',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: 'BlockB!Password44',
        mnemonicWords: _mnemonic,
      );
    });
    MasterKeyManager.instance.resetForTesting();

    await pumpRocen(tester);
    await tester.pumpAndSettle();
    await tester.tap(publicTab('SET'));
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.text('ROCEN LOCKED'), findsOneWidget);
    expect(find.text('SET UP ROCEN'), findsNothing);
    expect(publicTab('NOTE'), findsOneWidget);
    await tester.tap(publicTab('CLIP'));
    await tester.pumpAndSettle();
    expect(find.text('PUBLIC PREVIEW'), findsOneWidget);
    await tester.tap(publicTab('SET'));
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('corrupt local authority fails closed inside the public shell',
      (WidgetTester tester) async {
    await tester.runAsync(() => Hive.box('rocen_settings_box').put(
          'master_key_record_v1',
          jsonEncode(<String, Object>{
            'schema': 1,
            'revision': 1,
            'authority': 'invalid',
          }),
        ));

    await pumpRocen(tester);
    await tester.pumpAndSettle();
    await tester.tap(publicTab('SET'));
    await tester.pumpAndSettle();

    expect(find.textContaining('COULD NOT READ YOUR ACCOUNT'), findsOneWidget);
    expect(find.text('ROCEN LOCKED'), findsNothing);
    expect(find.text('SET UP ROCEN'), findsNothing,
        reason: 'corrupt authority is never treated as a first install');
    expect(publicTab('NOTE'), findsOneWidget);
    await tester.tap(publicTab('YEAR'));
    await tester.pumpAndSettle();
    expect(find.text('PUBLIC PREVIEW'), findsOneWidget);
    expect(
        Hive.box('rocen_settings_box').get('master_key_record_v1'), isNotNull,
        reason: 'preview navigation must not rewrite authority');
  });

  testWidgets(
      'GitHub restore entry opens password and GitHub dialogs without any '
      'network request or authority change', (WidgetTester tester) async {
    await pumpRocen(tester);
    await tester.pumpAndSettle();
    await tester.tap(publicTab('SET'));
    await tester.pumpAndSettle();

    expect(find.text('RESTORE EXISTING ACCOUNT FROM GITHUB'), findsOneWidget);
    await tester.tap(find.text('RESTORE EXISTING ACCOUNT FROM GITHUB'));
    await tester.pumpAndSettle();
    expect(find.text('ENTER YOUR EXISTING PASSWORD'), findsOneWidget);
    expect(publicTab('NOTE'), findsOneWidget,
        reason: 'the navbar stays available while restore is shown');

    await tester.enterText(find.byType(TextField), 'ExistingPassword1!');
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    expect(find.text('GITHUB ACCESS'), findsOneWidget);

    expect(networkProbe.clientsCreated, 0,
        reason: 'nothing contacts GitHub until a token and repository are '
            'confirmed');
    expect(Hive.box('rocen_settings_box').get('master_key_record_v1'), isNull);
    expect(Hive.box('rocen_settings_box').get('github_repo'), isNull);
  });
}
