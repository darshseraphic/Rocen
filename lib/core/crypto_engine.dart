import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:hive_flutter/hive_flutter.dart';
import 'bip39.dart';
import 'crypto_isolate.dart';
import 'secure_bytes.dart';

class KdfParams {
  final int memory;
  final int iterations;
  const KdfParams(this.memory, this.iterations);
}

class CryptoEngine {

  static final Sha256 _sha256 = Sha256();

  static const int _version = 1;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static const MethodChannel _integrityChannel = MethodChannel('com.darshseraphic.rocen/device_integrity');
  static bool? _cachedRootStatus;

  static const MethodChannel _secureKeystoreChannel = MethodChannel('com.darshseraphic.rocen/secure_keystore');

  static Future<bool> isDeviceRooted() async {
    if (_cachedRootStatus != null) return _cachedRootStatus!;
    try {
      final bool result = (await _integrityChannel.invokeMethod<bool>('isRooted')) ?? false;
      _cachedRootStatus = result;
      return result;
    } catch (_) {
      _cachedRootStatus = false;
      return false;
    }
  }

  static bool _isHardened() {
    try {
      final box = Hive.box('rocen_settings_box');
      return box.get('kdf_hardened', defaultValue: false) as bool;
    } catch (_) {
      return false;
    }
  }

  static const KdfParams _authParamsStandard = KdfParams(65536, 3);
  static const KdfParams _authParamsHardened = KdfParams(131072, 4);
  static const KdfParams _encryptionParamsStandard = KdfParams(65536, 3);
  static const KdfParams _encryptionParamsHardened = KdfParams(131072, 4);

  static KdfParams get _activeAuthParams => _isHardened() ? _authParamsHardened : _authParamsStandard;
  static KdfParams get _activeEncryptionParams => _isHardened() ? _encryptionParamsHardened : _encryptionParamsStandard;

  static Future<String> encryptProcess(String input, String pin) async {
    final Uint8List inputBytes = Uint8List.fromList(utf8.encode(input));

    final salt = _generateSecureBytes(_saltLength);
    final nonce = _generateSecureBytes(_nonceLength);
    final params = _activeEncryptionParams;

    final result = await CryptoIsolate.deriveAndEncrypt(
      plaintext: inputBytes,
      password: pin,
      salt: salt,
      nonce: nonce,
      memory: params.memory,
      iterations: params.iterations,
    );

    final package = BytesBuilder()
      ..add([_version])
      ..add(salt)
      ..add(nonce)
      ..add(result['mac']!)
      ..add(result['cipherText']!);

    return base64.encode(package.toBytes());
  }

  static Future<String> decryptProcess(String input, String pin) async {
    try {
      final bytes = base64.decode(input);

      if (bytes.isEmpty || bytes[0] != _version) {
        return 'DECRYPTION FAULT';
      }

      int offset = 1;

      final salt = bytes.sublist(offset, offset + _saltLength);
      offset += _saltLength;

      final nonce = bytes.sublist(offset, offset + _nonceLength);
      offset += _nonceLength;

      final mac = bytes.sublist(offset, offset + _macLength);
      offset += _macLength;

      final cipherText = bytes.sublist(offset);

      final params = _activeEncryptionParams;
      final clear = await CryptoIsolate.deriveAndDecrypt(
        cipherText: Uint8List.fromList(cipherText),
        mac: Uint8List.fromList(mac),
        password: pin,
        salt: Uint8List.fromList(salt),
        nonce: Uint8List.fromList(nonce),
        memory: params.memory,
        iterations: params.iterations,
      );

      if (clear == null) return 'DECRYPTION FAULT';

      // clear already crossed the isolate boundary as a normal (unpinned)
      // copy - that hop is outside our control (Isolate.run's own message
      // passing). We minimize exposure by immediately moving it into
      // RAM-locked memory and wiping the transient copy right away.
      final pinnedClear = SecureBytes(clear);
      zeroBytes(clear);
      try {
        return utf8.decode(pinnedClear.bytes);
      } finally {
        pinnedClear.zero();
      }
    } catch (_) {
      return 'DECRYPTION FAULT';
    }
  }

  static Map<String, String> splitForBackup(String fullPackageBase64) {
    final bytes = base64.decode(fullPackageBase64);

    final versionByte = bytes.sublist(0, 1);
    final salt = bytes.sublist(1, 1 + _saltLength);
    final nonce = bytes.sublist(1 + _saltLength, 1 + _saltLength + _nonceLength);
    final macAndCipher = bytes.sublist(1 + _saltLength + _nonceLength);

    final cypherPackage = BytesBuilder()
      ..add(versionByte)
      ..add(macAndCipher);

    return {
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'cyphertext': base64.encode(cypherPackage.toBytes()),
    };
  }

  static String mergeFromBackup(String saltBase64, String nonceBase64, String cyphertextBase64) {
    final saltBytes = base64.decode(saltBase64);
    final nonceBytes = base64.decode(nonceBase64);
    final cypherBytes = base64.decode(cyphertextBase64);

    final versionByte = cypherBytes.sublist(0, 1);
    final macAndCipher = cypherBytes.sublist(1);

    final fullPackage = BytesBuilder()
      ..add(versionByte)
      ..add(saltBytes)
      ..add(nonceBytes)
      ..add(macAndCipher);

    return base64.encode(fullPackage.toBytes());
  }

  static const int passwordLength = 8;

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
  static final RegExp _symbolPattern = RegExp(r'[!@#$%^&*()_=+\-\\/:;.,"~`{}\[\]|]');
  static final RegExp _fullAllowedPattern = RegExp(r'^[A-Za-z0-9!@#$%^&*()_=+\-\\/:;.,"~`{}\[\]|]{8}$');

  // Stricter composition rule: each of the 4 categories needs at least 2
  // characters, and those characters can't be identical to each other
  // within their own category (no "AA", no "11"). At exactly 8 total
  // characters, requiring 2 of each of the 4 categories uses up the whole
  // length - so this mathematically forces EXACTLY 2 per category, not
  // "2 or more". Also enforces: the same letter can't appear as both its
  // uppercase and lowercase form (no "Aa" pair), so case alone can't be
  // used to satisfy two categories with what's visually the same letter.
  static List<String> _uniqueCharsMatching(String candidate, RegExp pattern) {
    final matched = candidate.split('').where((c) => pattern.hasMatch(c)).toList();
    return matched.toSet().toList();
  }

  static bool isPasswordComplexityValid(String candidate) {
    if (!_fullAllowedPattern.hasMatch(candidate)) return false;

    final upperChars = candidate.split('').where((c) => _upperPattern.hasMatch(c)).toList();
    final lowerChars = candidate.split('').where((c) => _lowerPattern.hasMatch(c)).toList();
    final digitChars = candidate.split('').where((c) => _digitPattern.hasMatch(c)).toList();
    final symbolChars = candidate.split('').where((c) => _symbolPattern.hasMatch(c)).toList();

    if (upperChars.length < 2 || upperChars.toSet().length < 2) return false;
    if (lowerChars.length < 2 || lowerChars.toSet().length < 2) return false;
    if (digitChars.length < 2 || digitChars.toSet().length < 2) return false;
    if (symbolChars.length < 2 || symbolChars.toSet().length < 2) return false;

    final lowerLetters = lowerChars.map((c) => c.toLowerCase()).toSet();
    final upperLetters = upperChars.map((c) => c.toLowerCase()).toSet();
    if (lowerLetters.intersection(upperLetters).isNotEmpty) return false;

    return true;
  }

  static List<String> missingPasswordRequirements(String candidate) {
    final List<String> missing = [];
    if (candidate.length != passwordLength) missing.add('$passwordLength CHARACTERS');

    final upperUnique = _uniqueCharsMatching(candidate, _upperPattern);
    final lowerUnique = _uniqueCharsMatching(candidate, _lowerPattern);
    final digitUnique = _uniqueCharsMatching(candidate, _digitPattern);
    final symbolUnique = _uniqueCharsMatching(candidate, _symbolPattern);

    if (upperUnique.length < 2) missing.add('2 UNIQUE UPPERCASE');
    if (lowerUnique.length < 2) missing.add('2 UNIQUE LOWERCASE');
    if (digitUnique.length < 2) missing.add('2 UNIQUE DIGITS');
    if (symbolUnique.length < 2) missing.add('2 UNIQUE SYMBOLS');

    final lowerLetters = lowerUnique.map((c) => c.toLowerCase()).toSet();
    final upperLetters = upperUnique.map((c) => c.toLowerCase()).toSet();
    if (lowerLetters.intersection(upperLetters).isNotEmpty) {
      missing.add('NO SAME LETTER IN UPPER + LOWER');
    }

    return missing;
  }

  // Same 5 rules as missingPasswordRequirements, but returns every rule's
  // live satisfied/unsatisfied status (not just the unsatisfied ones) - for
  // UI that shows the full checklist at all times with an animated
  // strikethrough per rule as it becomes satisfied, rather than rules
  // disappearing outright the instant they're met.
  static List<(String label, bool satisfied)> passwordRequirementStatus(String candidate) {
    final upperUnique = _uniqueCharsMatching(candidate, _upperPattern);
    final lowerUnique = _uniqueCharsMatching(candidate, _lowerPattern);
    final digitUnique = _uniqueCharsMatching(candidate, _digitPattern);
    final symbolUnique = _uniqueCharsMatching(candidate, _symbolPattern);

    final lowerLetters = lowerUnique.map((c) => c.toLowerCase()).toSet();
    final upperLetters = upperUnique.map((c) => c.toLowerCase()).toSet();
    final noSharedCaseLetter = lowerLetters.intersection(upperLetters).isEmpty;

    return [
      ('2 UNIQUE UPPERCASE', upperUnique.length >= 2),
      ('2 UNIQUE LOWERCASE', lowerUnique.length >= 2),
      ('2 UNIQUE DIGITS', digitUnique.length >= 2),
      ('2 UNIQUE SYMBOLS', symbolUnique.length >= 2),
      ('NO SAME LETTER IN UPPER + LOWER', noSharedCaseLetter),
    ];
  }

  static Future<String> hashPin(String pin) async {
    final salt = _generateSecureBytes(_saltLength);
    return hashPinWithSalt(pin, salt);
  }

  static Future<String> hashPinWithSalt(String pin, Uint8List saltBytes) async {
    final params = _activeAuthParams;
    final hash = await CryptoIsolate.deriveKeyBytes(
      password: pin,
      salt: saltBytes,
      memory: params.memory,
      iterations: params.iterations,
    );

    return '${base64.encode(saltBytes)}:${base64.encode(hash)}';
  }

  static Future<bool> verifyPin(String pin, String stored) async {
    try {
      final parts = stored.split(':');
      if (parts.length != 2) return false;

      final salt = base64.decode(parts[0]);
      final expected = base64.decode(parts[1]);

      final params = _activeAuthParams;
      final actual = await CryptoIsolate.deriveKeyBytes(
        password: pin,
        salt: Uint8List.fromList(salt),
        memory: params.memory,
        iterations: params.iterations,
      );

      final pinnedActual = SecureBytes(actual);
      final pinnedExpected = SecureBytes(expected);
      zeroBytes(actual);
      zeroBytes(expected);
      try {
        return _constantTimeEquals(pinnedActual.bytes, pinnedExpected.bytes);
      } finally {
        pinnedActual.zero();
        pinnedExpected.zero();
      }
    } catch (_) {
      return false;
    }
  }

  static Uint8List extractAuthSalt(String stored) {
    return base64.decode(stored.split(':')[0]);
  }

  // Two independent hardware-backed keys, one per purpose - so a key
  // compromise (if that ever became possible) in one has zero implication
  // for the other. Each results in its own separate AndroidKeyStore entry.
  static const String passwordKeyAlias = 'rocen_hw_password_key';
  static const String githubTokenKeyAlias = 'rocen_hw_github_key';

  // Wraps an already-encrypted or plaintext string with the device's
  // StrongBox/TEE-backed AndroidKeyStore AES key for the given purpose, so
  // it can no longer be read from local storage alone (root access, ADB
  // backup, file copy). Returns null if the hardware keystore is
  // unavailable - callers must fall back to storing the unwrapped value.
  static Future<String?> hardwareWrap(String plaintext, {required String keyAlias}) async {
    try {
      final Uint8List plainBytes = Uint8List.fromList(utf8.encode(plaintext));
      final result = await _secureKeystoreChannel.invokeMapMethod<String, dynamic>(
        'hwEncrypt',
        {'plaintext': base64.encode(plainBytes), 'keyAlias': keyAlias},
      );
      if (result == null) return null;

      final String tier = (result['tier'] ?? 'tee').toString();
      try {
        final box = Hive.box('rocen_settings_box');
        await box.put('hw_key_tier_$keyAlias', tier);
      } catch (_) {}

      final package = jsonEncode({'iv': result['iv'], 'ct': result['ciphertext']});
      return 'HW1:${base64.encode(utf8.encode(package))}';
    } catch (_) {
      return null;
    }
  }

  // Reverses hardwareWrap. Returns null if the value wasn't hardware-wrapped,
  // or if the hardware key can't decrypt it (different device, wiped
  // Keystore, StrongBox unavailable) - callers treat null as "this device
  // can't be trusted for this value" rather than silently falling through.
  static Future<String?> hardwareUnwrap(String wrapped, {required String keyAlias}) async {
    try {
      if (!wrapped.startsWith('HW1:')) return null;
      final Map<String, dynamic> package = jsonDecode(utf8.decode(base64.decode(wrapped.substring(4))));

      final result = await _secureKeystoreChannel.invokeMapMethod<String, dynamic>(
        'hwDecrypt',
        {'iv': package['iv'], 'ciphertext': package['ct'], 'keyAlias': keyAlias},
      );
      if (result == null) return null;

      return utf8.decode(base64.decode(result['plaintext'].toString()));
    } catch (_) {
      return null;
    }
  }

  static Future<String> hardwareKeyTier({String keyAlias = passwordKeyAlias}) async {
    try {
      final String? tier = await _secureKeystoreChannel.invokeMethod<String>('keyTier', {'keyAlias': keyAlias});
      return tier ?? 'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  // Password verification gated on hardware device-binding. Behaves exactly
  // like verifyPin(), plus: once a hw_wrapped_pin exists for this install, a
  // successful password match ALSO requires the password-purpose hardware
  // key to unwrap it back to the same stored hash. If Keystore was wiped or
  // the storage was moved to another device, this fails even with the
  // correct password - by design, forcing the user through BIP-39 recovery
  // instead. If no hw_wrapped_pin exists yet (fresh upgrade from a
  // pre-hardware install), one is established transparently on this
  // successful verify.
  static Future<bool> verifyPinWithHardwareBinding(String pin, String storedHash) async {
    final bool softwareValid = await verifyPin(pin, storedHash);
    if (!softwareValid) return false;

    try {
      final box = Hive.box('rocen_settings_box');
      final String? hwWrapped = box.get('hw_wrapped_pin');

      if (hwWrapped == null) {
        final String? wrapped = await hardwareWrap(storedHash, keyAlias: passwordKeyAlias);
        if (wrapped != null) await box.put('hw_wrapped_pin', wrapped);
        return true;
      }

      final String? unwrapped = await hardwareUnwrap(hwWrapped, keyAlias: passwordKeyAlias);
      return unwrapped == storedHash;
    } catch (_) {
      return true;
    }
  }

  static Future<Map<String, String>> wrapDeviceKey({
    required Uint8List authSaltBytes,
    required String password,
    required List<String> mnemonicWords,
  }) async {
    final String combinedSecret = '$password|${mnemonicWords.join(' ').trim().toLowerCase()}';
    final wrapSalt = _generateSecureBytes(_saltLength);
    final wrapNonce = _generateSecureBytes(_nonceLength);
    final params = _activeEncryptionParams;

    final result = await CryptoIsolate.deriveAndEncrypt(
      plaintext: authSaltBytes,
      password: combinedSecret,
      salt: wrapSalt,
      nonce: wrapNonce,
      memory: params.memory,
      iterations: params.iterations,
    );

    final macAndCipher = BytesBuilder()
      ..add(result['mac']!)
      ..add(result['cipherText']!);

    return {
      'wrapSalt': base64.encode(wrapSalt),
      'wrapNonce': base64.encode(wrapNonce),
      'wrappedAuthSalt': base64.encode(macAndCipher.toBytes()),
    };
  }

  static Future<Uint8List?> unwrapDeviceKey({
    required String wrapSalt,
    required String wrapNonce,
    required String wrappedAuthSalt,
    required String password,
    required List<String> mnemonicWords,
  }) async {
    try {
      final String combinedSecret = '$password|${mnemonicWords.join(' ').trim().toLowerCase()}';
      final saltBytes = base64.decode(wrapSalt);
      final nonceBytes = base64.decode(wrapNonce);
      final macAndCipherBytes = base64.decode(wrappedAuthSalt);

      final macBytes = macAndCipherBytes.sublist(0, _macLength);
      final cipherBytes = macAndCipherBytes.sublist(_macLength);

      final params = _activeEncryptionParams;
      final clear = await CryptoIsolate.deriveAndDecrypt(
        cipherText: Uint8List.fromList(cipherBytes),
        mac: Uint8List.fromList(macBytes),
        password: combinedSecret,
        salt: Uint8List.fromList(saltBytes),
        nonce: Uint8List.fromList(nonceBytes),
        memory: params.memory,
        iterations: params.iterations,
      );

      return clear;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> generateMnemonic() async {
    final entropy = _generateSecureBytes(16);
    return _entropyToMnemonic(entropy);
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
    final List<String> words = [];
    for (int i = 0; i < 12; i++) {
      final chunk = bitString.substring(i * 11, i * 11 + 11);
      final index = int.parse(chunk, radix: 2);
      words.add(Bip39Wordlist.words[index]);
    }
    return words;
  }

  static bool isValidMnemonicWord(String word) {
    return Bip39Wordlist.words.contains(word.trim().toLowerCase());
  }

  static Future<bool> validateMnemonicChecksum(List<String> mnemonicWords) async {
    if (mnemonicWords.length != 12) return false;

    final List<int> indices = [];
    for (final w in mnemonicWords) {
      final idx = Bip39Wordlist.words.indexOf(w.trim().toLowerCase());
      if (idx == -1) return false;
      indices.add(idx);
    }

    final StringBuffer bits = StringBuffer();
    for (final idx in indices) {
      bits.write(idx.toRadixString(2).padLeft(11, '0'));
    }
    final String bitString = bits.toString();

    final String entropyBits = bitString.substring(0, 128);
    final String checksumBits = bitString.substring(128, 132);

    final Uint8List entropyBytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      entropyBytes[i] = int.parse(entropyBits.substring(i * 8, i * 8 + 8), radix: 2);
    }

    final hash = await _sha256.hash(entropyBytes);
    final String expectedChecksumBits = ((hash.bytes[0] >> 4) & 0x0F).toRadixString(2).padLeft(4, '0');

    return expectedChecksumBits == checksumBits;
  }

  static Uint8List _generateSecureBytes(int length) {
    final rnd = Random.secure();
    final values = Uint8List(length);
    for (int i = 0; i < length; i++) {
      values[i] = rnd.nextInt(256);
    }
    return values;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;

    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}