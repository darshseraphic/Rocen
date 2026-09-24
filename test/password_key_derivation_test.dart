import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/password_key_derivation.dart';

Uint8List _testMasterKey([int seed = 1]) {
  final rnd = Random(seed); // deterministic for test fixtures only
  return Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
}

const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

void main() {
  group('Password verifier', () {
    test('correct password verifies', () async {
      final v = await PasswordKeyDerivation.createPasswordVerifier('pw-correct');
      expect(await PasswordKeyDerivation.verifyPassword('pw-correct', v), isTrue);
    });

    test('wrong password fails', () async {
      final v = await PasswordKeyDerivation.createPasswordVerifier('pw-correct');
      expect(await PasswordKeyDerivation.verifyPassword('pw-wrong', v), isFalse);
    });

    test('malformed verifier fails closed, never throws', () async {
      expect(await PasswordKeyDerivation.verifyPassword('x', 'garbage'), isFalse);
      expect(await PasswordKeyDerivation.verifyPassword('x', ''), isFalse);
    });

    test('two verifiers for the SAME password differ (fresh salts)', () async {
      final a = await PasswordKeyDerivation.createPasswordVerifier('same');
      final b = await PasswordKeyDerivation.createPasswordVerifier('same');
      expect(a, isNot(equals(b)),
          reason: 'Each verifier must use an independent fresh salt.');
      // Both must still verify the same password.
      expect(await PasswordKeyDerivation.verifyPassword('same', a), isTrue);
      expect(await PasswordKeyDerivation.verifyPassword('same', b), isTrue);
    });
  });

  group('Verifier independence from Password-KEK', () {
    test(
        'the stored verifier CANNOT unwrap a Master Key wrapped under the '
        'same password (the Finding 3A fix)', () async {
      const password = 'shared-password';
      final mk = _testMasterKey();

      final verifier =
          await PasswordKeyDerivation.createPasswordVerifier(password);
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
        masterKeyBytes: mk,
        rawPassword: password,
      );

      // Feeding the verifier record (or its hash half) in place of the
      // password must not unwrap anything.
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: wrap, rawPassword: verifier),
        isNull,
      );
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: wrap, rawPassword: verifier.split(':')[1]),
        isNull,
        reason:
            'The stored verifier hash must be useless as encryption key '
            'material - this is the specific vulnerability Stage 3 exists '
            'to eliminate.',
      );
    });

    test('verifier salt and wrap salt are independent', () async {
      const password = 'p';
      final verifier =
          await PasswordKeyDerivation.createPasswordVerifier(password);
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
        masterKeyBytes: _testMasterKey(),
        rawPassword: password,
      );

      final verifierSalt = verifier.split(':')[0];
      final wrapSalt = (jsonDecode(wrap) as Map<String, dynamic>)['salt'];
      expect(verifierSalt, isNot(equals(wrapSalt)));
    });
  });

  group('Password-KEK wrap/unwrap', () {
    test('correct password unwraps the exact same Master Key', () async {
      final mk = _testMasterKey();
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: mk, rawPassword: 'pw');
      final out = await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
          wrapJson: wrap, rawPassword: 'pw');
      expect(out, equals(mk));
    });

    test('wrong password returns null, never partial key material', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: _testMasterKey(), rawPassword: 'pw');
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: wrap, rawPassword: 'wrong'),
        isNull,
      );
    });

    test('tampered ciphertext fails authentication', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: _testMasterKey(), rawPassword: 'pw');
      final m = jsonDecode(wrap) as Map<String, dynamic>;
      final ct = base64.decode(m['ct'] as String);
      ct[0] ^= 0xFF;
      m['ct'] = base64.encode(ct);

      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: jsonEncode(m), rawPassword: 'pw'),
        isNull,
      );
    });

    test('unsupported wrap version fails closed', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: _testMasterKey(), rawPassword: 'pw');
      final m = jsonDecode(wrap) as Map<String, dynamic>;
      m['v'] = 99;
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: jsonEncode(m), rawPassword: 'pw'),
        isNull,
      );
    });

    test('unsupported KDF identifier fails closed', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: _testMasterKey(), rawPassword: 'pw');
      final m = jsonDecode(wrap) as Map<String, dynamic>;
      m['kdf'] = 'sha256';
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: jsonEncode(m), rawPassword: 'pw'),
        isNull,
      );
    });

    test('remote-controlled KDF cost must match approved safe profile', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: _testMasterKey(), rawPassword: 'pw');
      final m = jsonDecode(wrap) as Map<String, dynamic>;
      m['memory'] = 1024 * 1024 * 1024;
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: jsonEncode(m), rawPassword: 'pw'),
        isNull,
      );
      m['memory'] = 65536;
      m['iterations'] = 1000000000;
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: jsonEncode(m), rawPassword: 'pw'),
        isNull,
      );
    });

    test('remote-controlled wrap binary lengths must be exact', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: _testMasterKey(), rawPassword: 'pw');
      final m = jsonDecode(wrap) as Map<String, dynamic>;
      m['salt'] = base64.encode(List<int>.filled(15, 1));
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: jsonEncode(m), rawPassword: 'pw'),
        isNull,
      );
      final clean = jsonDecode(wrap) as Map<String, dynamic>;
      clean['nonce'] = base64.encode(List<int>.filled(11, 2));
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: jsonEncode(clean), rawPassword: 'pw'),
        isNull,
      );
      final clean2 = jsonDecode(wrap) as Map<String, dynamic>;
      clean2['mac'] = base64.encode(List<int>.filled(15, 3));
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
            wrapJson: jsonEncode(clean2), rawPassword: 'pw'),
        isNull,
      );
    });

    test('wrap records its own KDF parameters explicitly', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: _testMasterKey(), rawPassword: 'pw');
      final m = jsonDecode(wrap) as Map<String, dynamic>;
      expect(m['memory'], isA<int>());
      expect(m['iterations'], isA<int>());
      expect(m['kdf'], equals('argon2id'));
    });

    test('two wraps of the same key+password differ (fresh salt/nonce)',
        () async {
      final mk = _testMasterKey();
      final a = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: mk, rawPassword: 'pw');
      final b = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: mk, rawPassword: 'pw');
      expect(a, isNot(equals(b)));
      // Both must still unwrap to the identical key.
      expect(await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
          wrapJson: a, rawPassword: 'pw'), equals(mk));
      expect(await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
          wrapJson: b, rawPassword: 'pw'), equals(mk));
    });
  });

  group('Recovery-KEK - BOTH factors mandatory', () {
    test('correct password + correct mnemonic recovers the Master Key',
        () async {
      final mk = _testMasterKey();
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
          masterKeyBytes: mk, rawPassword: 'pw', mnemonicWords: _mnemonic);
      final out = await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
          wrapJson: wrap, rawPassword: 'pw', mnemonicWords: _mnemonic);
      expect(out, equals(mk));
    });

    test('wrong password + correct mnemonic FAILS', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
          masterKeyBytes: _testMasterKey(),
          rawPassword: 'pw',
          mnemonicWords: _mnemonic);
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
            wrapJson: wrap, rawPassword: 'wrong', mnemonicWords: _mnemonic),
        isNull,
        reason:
            'Proves the mnemonic ALONE is insufficient - even the fully '
            'correct mnemonic fails without the correct password.',
      );
    });

    test('correct password + wrong mnemonic FAILS', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
          masterKeyBytes: _testMasterKey(),
          rawPassword: 'pw',
          mnemonicWords: _mnemonic);
      final wrongMnemonic = List<String>.from(_mnemonic)..[0] = 'zoo';
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
            wrapJson: wrap, rawPassword: 'pw', mnemonicWords: wrongMnemonic),
        isNull,
        reason:
            'Proves the password ALONE is insufficient for the recovery '
            'path - both factors are genuinely required.',
      );
    });

    test('both wrong FAILS', () async {
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
          masterKeyBytes: _testMasterKey(),
          rawPassword: 'pw',
          mnemonicWords: _mnemonic);
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
            wrapJson: wrap,
            rawPassword: 'wrong',
            mnemonicWords: List<String>.from(_mnemonic)..[0] = 'zoo'),
        isNull,
      );
    });

    test('a Password-KEK wrap cannot be unwrapped by the recovery path',
        () async {
      final mk = _testMasterKey();
      final pwWrap = await PasswordKeyDerivation.wrapMasterKeyWithPassword(
          masterKeyBytes: mk, rawPassword: 'pw');
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
            wrapJson: pwWrap, rawPassword: 'pw', mnemonicWords: _mnemonic),
        isNull,
        reason:
            'The two derivation inputs are genuinely distinct - a wrap made '
            'under one must not open under the other.',
      );
    });

    test('mnemonic case/order normalization is deterministic', () async {
      final mk = _testMasterKey();
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
          masterKeyBytes: mk, rawPassword: 'pw', mnemonicWords: _mnemonic);

      // Re-entered with different capitalization - must still recover,
      // proving Stage 1's canonical normalization is actually applied.
      final mixedCase = _mnemonic.map((w) => w.toUpperCase()).toList();
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
            wrapJson: wrap, rawPassword: 'pw', mnemonicWords: mixedCase),
        equals(mk),
      );
    });
  });

  group('Password change - re-wrap only', () {
    test('same MK survives password change through both wrapping paths',
        () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);

      final result = await PasswordKeyDerivation.changePassword(
        existingPasswordWrapJson: oldPasswordWrap,
        existingRecoveryWrapJson: oldRecoveryWrap,
        oldRawPassword: 'old-pw',
        newRawPassword: 'new-pw',
        mnemonicWords: _mnemonic,
      );

      expect(result, isNotNull);
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
          wrapJson: result!.newPasswordWrapJson,
          rawPassword: 'new-pw',
        ),
        equals(mk),
      );
      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
          wrapJson: result.newRecoveryWrapJson,
          rawPassword: 'new-pw',
          mnemonicWords: _mnemonic,
        ),
        equals(mk),
      );
    });

    test('old password cannot open the new Password-KEK wrap', () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);
      final result = await PasswordKeyDerivation.changePassword(
        existingPasswordWrapJson: oldPasswordWrap,
        existingRecoveryWrapJson: oldRecoveryWrap,
        oldRawPassword: 'old-pw',
        newRawPassword: 'new-pw',
        mnemonicWords: _mnemonic,
      );

      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithPassword(
          wrapJson: result!.newPasswordWrapJson,
          rawPassword: 'old-pw',
        ),
        isNull,
      );
    });

    test('old password + mnemonic cannot open the new Recovery-KEK wrap',
        () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);
      final result = await PasswordKeyDerivation.changePassword(
        existingPasswordWrapJson: oldPasswordWrap,
        existingRecoveryWrapJson: oldRecoveryWrap,
        oldRawPassword: 'old-pw',
        newRawPassword: 'new-pw',
        mnemonicWords: _mnemonic,
      );

      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
          wrapJson: result!.newRecoveryWrapJson,
          rawPassword: 'old-pw',
          mnemonicWords: _mnemonic,
        ),
        isNull,
      );
    });

    test('new password + correct mnemonic opens the new Recovery-KEK wrap',
        () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);
      final result = await PasswordKeyDerivation.changePassword(
        existingPasswordWrapJson: oldPasswordWrap,
        existingRecoveryWrapJson: oldRecoveryWrap,
        oldRawPassword: 'old-pw',
        newRawPassword: 'new-pw',
        mnemonicWords: _mnemonic,
      );

      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
          wrapJson: result!.newRecoveryWrapJson,
          rawPassword: 'new-pw',
          mnemonicWords: _mnemonic,
        ),
        equals(mk),
      );
    });

    test('wrong mnemonic cannot open the new Recovery-KEK wrap', () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);
      final result = await PasswordKeyDerivation.changePassword(
        existingPasswordWrapJson: oldPasswordWrap,
        existingRecoveryWrapJson: oldRecoveryWrap,
        oldRawPassword: 'old-pw',
        newRawPassword: 'new-pw',
        mnemonicWords: _mnemonic,
      );
      final wrongMnemonic = List<String>.from(_mnemonic)..[0] = 'zoo';

      expect(
        await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
          wrapJson: result!.newRecoveryWrapJson,
          rawPassword: 'new-pw',
          mnemonicWords: wrongMnemonic,
        ),
        isNull,
      );
    });

    test('wrong old password cannot perform password change', () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);

      expect(
        await PasswordKeyDerivation.changePassword(
          existingPasswordWrapJson: oldPasswordWrap,
          existingRecoveryWrapJson: oldRecoveryWrap,
          oldRawPassword: 'wrong-old-pw',
          newRawPassword: 'new-pw',
          mnemonicWords: _mnemonic,
        ),
        isNull,
      );
    });

    test('existing recovery wrapper must match the password-unwrapped MK',
        () async {
      final mkA = _testMasterKey(1);
      final mkB = _testMasterKey(2);
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mkA, rawPassword: 'old-pw');
      final wrongRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mkB,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);

      expect(
        await PasswordKeyDerivation.changePassword(
          existingPasswordWrapJson: oldPasswordWrap,
          existingRecoveryWrapJson: wrongRecoveryWrap,
          oldRawPassword: 'old-pw',
          newRawPassword: 'new-pw',
          mnemonicWords: _mnemonic,
        ),
        isNull,
      );
    });

    test('password change uses fresh salts/nonces for both new wraps',
        () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);

      final oldPasswordMap = jsonDecode(oldPasswordWrap) as Map<String, dynamic>;
      final oldRecoveryMap = jsonDecode(oldRecoveryWrap) as Map<String, dynamic>;
      final result = await PasswordKeyDerivation.changePassword(
        existingPasswordWrapJson: oldPasswordWrap,
        existingRecoveryWrapJson: oldRecoveryWrap,
        oldRawPassword: 'old-pw',
        newRawPassword: 'new-pw',
        mnemonicWords: _mnemonic,
      );
      expect(result, isNotNull);

      final newPasswordMap =
          jsonDecode(result!.newPasswordWrapJson) as Map<String, dynamic>;
      final newRecoveryMap =
          jsonDecode(result.newRecoveryWrapJson) as Map<String, dynamic>;

      expect(newPasswordMap['salt'], isNot(equals(oldPasswordMap['salt'])));
      expect(newPasswordMap['nonce'], isNot(equals(oldPasswordMap['nonce'])));
      expect(newRecoveryMap['salt'], isNot(equals(oldRecoveryMap['salt'])));
      expect(newRecoveryMap['nonce'], isNot(equals(oldRecoveryMap['nonce'])));
    });

    test('password change produces a fresh verifier salt', () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);
      final oldVerifier =
          await PasswordKeyDerivation.createPasswordVerifier('old-pw');
      final result = await PasswordKeyDerivation.changePassword(
        existingPasswordWrapJson: oldPasswordWrap,
        existingRecoveryWrapJson: oldRecoveryWrap,
        oldRawPassword: 'old-pw',
        newRawPassword: 'new-pw',
        mnemonicWords: _mnemonic,
      );

      expect(result, isNotNull);
      expect(result!.newVerifier.split(':')[0],
          isNot(equals(oldVerifier.split(':')[0])));
      expect(await PasswordKeyDerivation.verifyPassword(
          'new-pw', result.newVerifier), isTrue);
      expect(await PasswordKeyDerivation.verifyPassword(
          'old-pw', result.newVerifier), isFalse);
    });

    test('password change result contains no note/token data', () async {
      final mk = _testMasterKey();
      final oldPasswordWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithPassword(
              masterKeyBytes: mk, rawPassword: 'old-pw');
      final oldRecoveryWrap =
          await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
              masterKeyBytes: mk,
              rawPassword: 'old-pw',
              mnemonicWords: _mnemonic);
      final result = await PasswordKeyDerivation.changePassword(
        existingPasswordWrapJson: oldPasswordWrap,
        existingRecoveryWrapJson: oldRecoveryWrap,
        oldRawPassword: 'old-pw',
        newRawPassword: 'new-pw',
        mnemonicWords: _mnemonic,
      );

      expect(result, isNotNull);
      expect(result!.newPasswordWrapJson.contains('note'), isFalse);
      expect(result.newPasswordWrapJson.contains('token'), isFalse);
      expect(result.newRecoveryWrapJson.contains('note'), isFalse);
      expect(result.newRecoveryWrapJson.contains('token'), isFalse);
      expect(result.newVerifier.contains('note'), isFalse);
      expect(result.newVerifier.contains('token'), isFalse);
    });
  });

  group('No plaintext persistence', () {
    test('a wrap contains neither the password nor the mnemonic', () async {
      const password = 'MyVerySecretPassword123';
      final wrap = await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
          masterKeyBytes: _testMasterKey(),
          rawPassword: password,
          mnemonicWords: _mnemonic);

      expect(wrap.contains(password), isFalse);
      for (final word in _mnemonic) {
        expect(wrap.contains(word), isFalse,
            reason: 'Mnemonic word "$word" must not appear in the wrap.');
      }
    });

    test('a verifier contains neither the password nor the Master Key',
        () async {
      const password = 'MyVerySecretPassword123';
      final mk = _testMasterKey();
      final verifier =
          await PasswordKeyDerivation.createPasswordVerifier(password);

      expect(verifier.contains(password), isFalse);
      expect(verifier.contains(base64.encode(mk)), isFalse);
    });
  });
}
