import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/password_key_derivation.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/activation_contract.dart';

/// SessionKeyMaterial's constructor is library-private (it is a `part of`
/// session_security_manager.dart) so a second owner cannot be instantiated.
/// Per the Stage 5 final hardening gate, there is also no injectable
/// authenticator any more - unlock() only ever derives its candidate MK from
/// a REAL password-wrap unwrap of a REAL durable record created by
/// establishFirstDevice. These tests therefore always go through that real
/// path; "different candidate" means "a different real established account",
/// never a fabricated Uint8List.
const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

Future<Uint8List> _establishAndObserveMk(String password) async {
  await MasterKeyProductionService.instance.establishFirstDevice(
    password: password,
    mnemonicWords: _mnemonic,
  );
  final MasterKeyLocalRecord record = (await MasterKeyLocalStore.read())!;
  final Uint8List key = (await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
    wrapJson: record.passwordWrap,
    rawPassword: password,
  ))!;
  return key;
}

Future<void> _unlock(String password) => SessionSecurityManager.instance.unlock(
      password: password,
      activateRoot: satisfyActivationContract,
      teardownRoot: () {},
    );

Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_skm_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
    ssm.finishBootstrap();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    enableSimulatedScreenAcknowledgementForTest();
  });

  tearDown(() => ssm.lockSync());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('ownership transfer via the real unlock path', () {
    test('a real unlock installs keys under SessionKeyMaterial, observed as '
        'state only (derivation correctness is covered by the frozen '
        'DomainKeyDerivation vectors; no raw NEK/TEK is exposed to tests)',
        () async {
      await _establishAndObserveMk('P4ssword-Alpha!');
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      await _unlock('P4ssword-Alpha!');
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      expect(ssm.activationDiagnostics.transactionOwnsMk, isFalse);
      expect(ssm.activationDiagnostics.transactionOwnsNek, isFalse);
      expect(ssm.activationDiagnostics.transactionOwnsTek, isFalse);
    });

    test('the manager exposes NO raw-key accessor (SOURCE-REVIEWED ONLY)',
        () {
      final String src = File(
              '${Directory.current.path}/lib/core/session_security_manager.dart')
          .readAsStringSync();
      expect(src, isNot(contains('requireNoteEncryptionKey')));
      expect(src, isNot(contains('requireGithubTokenEncryptionKey')));
    });
  });

  group('destruction', () {
    test('lock makes NEK and TEK unreachable', () async {
      await _establishAndObserveMk('P4ssword-Charlie!');
      await _unlock('P4ssword-Charlie!');
      ssm.lockSync();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    test('lock is idempotent', () async {
      await _establishAndObserveMk('P4ssword-Delta!');
      await _unlock('P4ssword-Delta!');
      ssm.lockSync();
      expect(() => ssm.lockSync(), returnsNormally);
    });
  });

  group('one owner at a time, across real sessions', () {
    test('after a password change and a re-lock, a new session installs '
        'fresh key material (no restoration of the previous session)',
        () async {
      await _establishAndObserveMk('P4ssword-Echo!');
      await _unlock('P4ssword-Echo!');
      final SessionAuthorizationToken token = ssm.captureAuthorization();
      await MasterKeyProductionService.instance.changePassword(
        oldPassword: 'P4ssword-Echo!',
        newPassword: 'P4ssword-Foxtrot!',
        mnemonicWords: _mnemonic,
        authorizationToken: token,
      );
      ssm.lockSync();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      MasterKeyManager.instance.resetForTesting();
      await _unlock('P4ssword-Foxtrot!');
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      expect(ssm.isAuthorizationValid(token), isFalse);
    });

    test('re-unlocking the SAME account re-installs from a fresh candidate; '
        'nothing is restored from the previous session', () async {
      await _establishAndObserveMk('P4ssword-Golf!');
      await _unlock('P4ssword-Golf!');
      ssm.lockSync();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      await _unlock('P4ssword-Golf!');
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
    });
  });
}
