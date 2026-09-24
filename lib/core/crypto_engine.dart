import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show MethodChannel;

import 'bip39.dart';

/// Small non-key-management utility surface retained during the Block B
/// cutover. Master-key wrapping/verification and all persistent data
/// encryption live in their dedicated Stage 3/4 components.
class CryptoEngine {
  CryptoEngine._();

  static const MethodChannel _integrityChannel =
      MethodChannel('com.darshseraphic.rocen/device_integrity');
  static const MethodChannel _secureKeystoreStatusChannel =
      MethodChannel('com.darshseraphic.rocen/secure_keystore');
  static final Sha256 _sha256 = Sha256();
  static bool? _cachedRootStatus;

  static Future<bool> isDeviceRooted() async {
    if (_cachedRootStatus != null) return _cachedRootStatus!;
    try {
      final bool result =
          (await _integrityChannel.invokeMethod<bool>('isRooted')) ?? false;
      _cachedRootStatus = result;
      return result;
    } catch (_) {
      _cachedRootStatus = true;
      return true;
    }
  }

  /// Reports the platform's configured hardware-key tier only. This does not
  /// create, wrap, unwrap, persist, or use any hardware-backed data key; that
  /// architecture remains outside Block B and belongs to the later stage.
  static Future<String> hardwareKeyTier({
    String keyAlias = 'rocen_hw_password_key',
  }) async {
    try {
      final String? tier = await _secureKeystoreStatusChannel
          .invokeMethod<String>('keyTier', {'keyAlias': keyAlias});
      return tier ?? 'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  static const int passwordMinLength = 8;
  static const int passwordMaxLength = 32;

  static int lockoutSecondsForAttempt(int attemptNumber) {
    if (attemptNumber < 2) return 0;
    if (attemptNumber == 2) return 30;
    if (attemptNumber == 3) return 60;
    final int stepsAfterThird = attemptNumber - 4;
    return 300 * (1 << stepsAfterThird);
  }

  static final RegExp _upperPattern = RegExp(r'[A-Z]');
  static final RegExp _lowerPattern = RegExp(r'[a-z]');
  static final RegExp _digitPattern = RegExp(r'[0-9]');
  static final RegExp _symbolPattern =
      RegExp(r'[!@#$%^&*()_=+\-\\/:;. ,"~`{}\[\]|]'.replaceAll(' ', ''));
  static final RegExp _fullAllowedPattern =
      RegExp(r'^[A-Za-z0-9!@#$%^&*()_=+\-\\/:;. ,"~`{}\[\]|]{8,32}$'.replaceAll(' ', ''));

  static bool isPasswordComplexityValid(String candidate) {
    if (!_fullAllowedPattern.hasMatch(candidate)) return false;
    final upper = candidate.split('').where(_upperPattern.hasMatch).toSet();
    final lower = candidate.split('').where(_lowerPattern.hasMatch).toSet();
    final digits = candidate.split('').where(_digitPattern.hasMatch).toSet();
    final symbols = candidate.split('').where(_symbolPattern.hasMatch).toSet();
    if (upper.length < 2 || lower.length < 2 || digits.length < 2 || symbols.length < 2) {
      return false;
    }
    final lowerLetters = lower.map((c) => c.toLowerCase()).toSet();
    final upperLetters = upper.map((c) => c.toLowerCase()).toSet();
    if (lowerLetters.intersection(upperLetters).isNotEmpty) return false;
    return true;
  }

  static List<(String, bool)> passwordRequirementStatus(String candidate) {
    final upper = candidate.split('').where(_upperPattern.hasMatch).toSet();
    final lower = candidate.split('').where(_lowerPattern.hasMatch).toSet();
    final digits = candidate.split('').where(_digitPattern.hasMatch).toSet();
    final symbols = candidate.split('').where(_symbolPattern.hasMatch).toSet();
    final lowerLetters = lower.map((c) => c.toLowerCase()).toSet();
    final upperLetters = upper.map((c) => c.toLowerCase()).toSet();
    return [
      ('2 UNIQUE UPPERCASE', upper.length >= 2),
      ('2 UNIQUE LOWERCASE', lower.length >= 2),
      ('2 UNIQUE DIGITS', digits.length >= 2),
      ('2 UNIQUE SYMBOLS', symbols.length >= 2),
      ('NO SAME LETTER IN UPPER + LOWER',
          lowerLetters.intersection(upperLetters).isEmpty),
    ];
  }

  static Future<List<String>> generateMnemonic() async {
    final Random random = Random.secure();
    final Uint8List entropy = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    try {
      return await _entropyToMnemonic(entropy);
    } finally {
      for (int i = 0; i < entropy.length; i++) {
        entropy[i] = 0;
      }
    }
  }

  static Future<List<String>> _entropyToMnemonic(Uint8List entropy) async {
    final hash = await _sha256.hash(entropy);
    final int checksumBits = (hash.bytes[0] >> 4) & 0x0F;
    final StringBuffer bits = StringBuffer();
    for (final byte in entropy) {
      bits.write(byte.toRadixString(2).padLeft(8, '0'));
    }
    bits.write(checksumBits.toRadixString(2).padLeft(4, '0'));
    final String bitString = bits.toString();
    return List<String>.generate(12, (i) {
      final chunk = bitString.substring(i * 11, i * 11 + 11);
      return Bip39Wordlist.words[int.parse(chunk, radix: 2)];
    });
  }

  static bool isValidMnemonicWord(String word) {
    return Bip39Wordlist.words.contains(word.trim().toLowerCase());
  }

  static Future<bool> validateMnemonicChecksum(
      List<String> mnemonicWords) async {
    if (mnemonicWords.length != 12) return false;
    final List<int> indices = <int>[];
    for (final word in mnemonicWords) {
      final index = Bip39Wordlist.words.indexOf(word.trim().toLowerCase());
      if (index < 0) return false;
      indices.add(index);
    }
    final String bitString = indices
        .map((i) => i.toRadixString(2).padLeft(11, '0'))
        .join();
    final String entropyBits = bitString.substring(0, 128);
    final String checksumBits = bitString.substring(128, 132);
    final Uint8List entropy = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      entropy[i] = int.parse(
        entropyBits.substring(i * 8, i * 8 + 8),
        radix: 2,
      );
    }
    final hash = await _sha256.hash(entropy);
    final String expected =
        ((hash.bytes[0] >> 4) & 0x0F).toRadixString(2).padLeft(4, '0');
    return expected == checksumBits;
  }
}
