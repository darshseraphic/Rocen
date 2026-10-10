import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Rocen/core/master_key_local_store.dart';
import 'package:Rocen/core/master_key_manager.dart';
import 'package:Rocen/core/master_key_production_service.dart';
import 'package:Rocen/core/password_key_derivation.dart';
import 'package:Rocen/core/session_unlock_service.dart';

const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

const String _password = 'BlockB!Password44';

/// The plaintext MK is never exposed by MasterKeyProductionService or
/// MasterKeyManager any more, so tests obtain the "expected" key by
/// independently unwrapping the durable record - exactly what a real unlock
/// does - and compare against what SessionUnlockService returns.
Future<Uint8List> _expectedMkFromDurableRecord() async {
  final MasterKeyLocalRecord record = (await MasterKeyLocalStore.read())!;
  final Uint8List? key = await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
    wrapJson: record.passwordWrap,
    rawPassword: _password,
  );
  return key!;
}

Future<void> main() async {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_unlock_service_test_');
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

  Future<void> establish() =>
      MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );

  test('hasLocalAuthority is false with no record', () async {
    expect(await SessionUnlockService.instance.hasLocalAuthority(), isFalse);
  });

  test('hasLocalAuthority is true after establishFirstDevice', () async {
    await establish();
    expect(await SessionUnlockService.instance.hasLocalAuthority(), isTrue);
  });

  test('unlockWithPassword throws NoLocalAuthorityException with no record',
      () async {
    await expectLater(
      SessionUnlockService.instance.unlockWithPassword(_password),
      throwsA(isA<NoLocalAuthorityException>()),
    );
  });

  test('cold start: no live MK anywhere before unlock, and unlock needs only '
      'the password', () async {
    await establish();
    // After establishment the manager holds nothing and its state is
    // operation-scoped, so it is back to idle.
    expect(MasterKeyManager.instance.state, MasterKeyState.none);

    final Uint8List expected = await _expectedMkFromDurableRecord();
    final Uint8List unlocked =
        await SessionUnlockService.instance.unlockWithPassword(_password);

    expect(unlocked, equals(expected));
    // Acknowledgement was operation-scoped: nothing lingers afterwards.
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    unlocked.fillRange(0, unlocked.length, 0);
    expected.fillRange(0, expected.length, 0);
  });

  test('second unlock re-unwraps from the durable record every time', () async {
    await establish();
    final Uint8List first =
        await SessionUnlockService.instance.unlockWithPassword(_password);
    final Uint8List second =
        await SessionUnlockService.instance.unlockWithPassword(_password);

    // Same MK (same durable authority) ...
    expect(second, equals(first));
    // ... but two independent buffers: nothing is cached and handed back.
    expect(identical(first, second), isFalse);
    first.fillRange(0, first.length, 0);
    expect(second, isNot(everyElement(0)),
        reason: 'zeroing one returned buffer must not affect another');
    second.fillRange(0, second.length, 0);
  });

  test('wrong password: rejected and nothing is acknowledged', () async {
    await establish();
    await expectLater(
      SessionUnlockService.instance.unlockWithPassword('wrong password entirely'),
      throwsA(isA<UnlockAuthenticationFailedException>()),
    );
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
  });

  test('repeated wrong-password attempts never establish authority', () async {
    await establish();
    for (int i = 0; i < 3; i++) {
      await expectLater(
        SessionUnlockService.instance.unlockWithPassword('attempt $i wrong'),
        throwsA(isA<UnlockAuthenticationFailedException>()),
      );
    }
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
  });

  test('unlockWithPassword never mutates the durable local record', () async {
    await establish();
    final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;

    final Uint8List unlocked =
        await SessionUnlockService.instance.unlockWithPassword(_password);
    unlocked.fillRange(0, unlocked.length, 0);

    final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
    expect(after.revision, before.revision);
    expect(after.passwordWrap, before.passwordWrap);
    expect(after.recoveryWrap, before.recoveryWrap);
  });

  test('unlock while another exclusive operation is in flight shares it '
      'rather than nesting or deadlocking', () async {
    await establish();
    final Future<Uint8List> a =
        SessionUnlockService.instance.unlockWithPassword(_password);
    final Future<Uint8List> b =
        SessionUnlockService.instance.unlockWithPassword(_password);
    final Uint8List ka = await a;
    final Uint8List kb = await b;
    expect(ka, equals(kb));
    ka.fillRange(0, ka.length, 0);
    kb.fillRange(0, kb.length, 0);
  });
}
