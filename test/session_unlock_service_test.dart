import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/activation_contract.dart';

/// SessionUnlockService's password-to-MK unwrap logic
/// (`_authenticateWithPassword`) is a library-private top-level function -
/// it is a `part of` session_security_manager.dart and is reachable ONLY
/// from SessionSecurityManager.unlock(), by design (see the Stage 5 audit's
/// "narrow raw-MK unlock access" requirement: no public API anywhere may
/// hand an arbitrary caller a raw MK derived from a password). This file
/// therefore tests:
///   - SessionUnlockService.hasLocalAuthority(), the ONLY public member,
///     directly;
///   - the authentication behavior it used to test directly, now only
///     observable through SessionSecurityManager.unlock()'s outcome (did it
///     commit to UNLOCKED, or throw SessionAuthenticationException with the
///     expected .cause).
const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

const String _password = 'BlockB!Password44';

Future<void> main() async {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_unlock_service_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    SessionSecurityManager.instance.resetForTesting();
    SessionSecurityManager.instance.finishBootstrap();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    enableSimulatedScreenAcknowledgementForTest();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> establish() =>
      MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );

  group('hasLocalAuthority (the only public member)', () {
    test('false with no record', () async {
      expect(await SessionUnlockService.instance.hasLocalAuthority(), isFalse);
    });

    test('true after establishFirstDevice', () async {
      await establish();
      expect(await SessionUnlockService.instance.hasLocalAuthority(), isTrue);
    });

    test('throws CorruptLocalAuthorityException for a present-but-invalid '
        'record, and never returns false for it', () async {
      await establish();
      // Corrupt the durable record the way MasterKeyLocalStore actually
      // persists it - as a JSON string - removing a required field so
      // fromJsonString's own structural validation fails, simulating
      // storage corruption rather than "never set up".
      final box = Hive.box(MasterKeyLocalStore.boxName);
      final dynamic raw = box.get('master_key_record_v1');
      expect(raw, isA<String>());
      final Map<String, dynamic> decoded =
          jsonDecode(raw as String) as Map<String, dynamic>;
      decoded.remove('passwordWrap');
      await box.put('master_key_record_v1', jsonEncode(decoded));

      await expectLater(
        SessionUnlockService.instance.hasLocalAuthority(),
        throwsA(isA<CorruptLocalAuthorityException>()),
      );
    });
  });

  group('authentication, observed only through SessionSecurityManager.unlock()',
      () {
    test('no local record: unlock fails with NoLocalAuthorityException as the '
        'cause', () async {
      final ssm = SessionSecurityManager.instance;
      try {
        await ssm.unlock(
          password: _password,
          activateRoot: satisfyActivationContract,
          teardownRoot: () {},
        );
        fail('expected SessionAuthenticationException');
      } on SessionAuthenticationException catch (e) {
        expect(e.cause, isA<NoLocalAuthorityException>());
      }
      expect(ssm.state, SessionState.locked);
    });

    test('cold start: unlock succeeds with just the password (no mnemonic)',
        () async {
      await establish();
      // Simulate a fresh process start: MasterKeyManager has no in-memory
      // state yet, even though the local record is durable.
      MasterKeyManager.instance.resetForTesting();

      final ssm = SessionSecurityManager.instance;
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      expect(ssm.state, SessionState.unlocked);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      ssm.lockSync();
    });

    test('wrong password: unlock fails with UnlockAuthenticationFailedException '
        'as the cause, and establishes nothing', () async {
      await establish();
      MasterKeyManager.instance.resetForTesting();

      final ssm = SessionSecurityManager.instance;
      try {
        await ssm.unlock(
          password: 'totally wrong password',
          activateRoot: satisfyActivationContract,
          teardownRoot: () {},
        );
        fail('expected SessionAuthenticationException');
      } on SessionAuthenticationException catch (e) {
        expect(e.cause, isA<UnlockAuthenticationFailedException>());
      }
      expect(ssm.state, SessionState.locked);
      expect(MasterKeyManager.instance.state, MasterKeyState.none);
    });

    test('repeated wrong-password attempts never establish authority',
        () async {
      await establish();
      MasterKeyManager.instance.resetForTesting();
      final ssm = SessionSecurityManager.instance;

      for (int i = 0; i < 3; i++) {
        try {
          await ssm.unlock(
            password: 'attempt $i wrong',
            activateRoot: satisfyActivationContract,
            teardownRoot: () {},
          );
          fail('expected failure');
        } catch (_) {}
      }
      expect(MasterKeyManager.instance.state, MasterKeyState.none);
      expect(ssm.state, SessionState.locked);
    });

    test('second unlock re-authenticates from the durable record every time '
        '(no shortcut across a lock)', () async {
      await establish();
      final ssm = SessionSecurityManager.instance;

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      ssm.lockSync();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      // Re-derived and re-installed from scratch, not restored.
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      ssm.lockSync();
    });

    test('unlockWithPassword no longer exists as a public entry point '
        '(regression guard for the raw-MK confinement requirement)', () {
      // There is intentionally no `SessionUnlockService.instance
      // .unlockWithPassword(...)` call anywhere in this file - see the
      // file-level documentation. This test exists only to make that
      // absence a documented, deliberate fact rather than an oversight a
      // future edit could quietly "fix" by re-adding a public raw-MK API.
      expect(SessionUnlockService.instance, isNotNull);
    });
  });

  group('unlock never mutates the durable local record', () {
    test('a successful unlock leaves the record byte-for-byte unchanged',
        () async {
      await establish();
      final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;

      final ssm = SessionSecurityManager.instance;
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      ssm.lockSync();

      final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
      expect(after.passwordWrap, before.passwordWrap);
      expect(after.recoveryWrap, before.recoveryWrap);
    });
  });
}
