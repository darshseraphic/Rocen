import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'bip39.dart';

class CryptoEngine {

  static final Sha256 _sha256 = Sha256();

  static const int _version = 1;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final AesGcm _cipher = AesGcm.with256bits();

  static final Argon2id _authKdf = Argon2id(
    memory: 65536,
    iterations: 3,
    parallelism: 1,
    hashLength: 32,
  );

  static final Argon2id _encryptionKdf = Argon2id(
    memory: 65536,
    iterations: 3,
    parallelism: 1,
    hashLength: 32,
  );

  static Future<String> encryptProcess(String input, String pin) async {
    final inputBytes = utf8.encode(input);

    final salt = _generateSecureBytes(_saltLength);
    final nonce = _generateSecureBytes(_nonceLength);

    final secretKey = await _encryptionKdf.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );

    final secretBox = await _cipher.encrypt(
      inputBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    final package = BytesBuilder()
      ..add([_version])
      ..add(salt)
      ..add(secretBox.nonce)
      ..add(secretBox.mac.bytes)
      ..add(secretBox.cipherText);

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

      final secretKey = await _encryptionKdf.deriveKeyFromPassword(
        password: pin,
        nonce: salt,
      );

      final box = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(mac),
      );

      final clear = await _cipher.decrypt(
        box,
        secretKey: secretKey,
      );

      return utf8.decode(clear);
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

  static const int passwordLength = 6;

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
  static final RegExp _fullAllowedPattern = RegExp(r'^[A-Za-z0-9!@#$%^&*()_=+\-\\/:;.,"~`{}\[\]|]{6}$');

  static bool isPasswordComplexityValid(String candidate) {
    if (!_fullAllowedPattern.hasMatch(candidate)) return false;
    if (!_upperPattern.hasMatch(candidate)) return false;
    if (!_lowerPattern.hasMatch(candidate)) return false;
    if (!_digitPattern.hasMatch(candidate)) return false;
    if (!_symbolPattern.hasMatch(candidate)) return false;
    return true;
  }

  static List<String> missingPasswordRequirements(String candidate) {
    final List<String> missing = [];
    if (candidate.length != passwordLength) missing.add('$passwordLength CHARACTERS');
    if (!_upperPattern.hasMatch(candidate)) missing.add('1 UPPERCASE');
    if (!_lowerPattern.hasMatch(candidate)) missing.add('1 LOWERCASE');
    if (!_digitPattern.hasMatch(candidate)) missing.add('1 DIGIT');
    if (!_symbolPattern.hasMatch(candidate)) missing.add('1 SYMBOL');
    return missing;
  }

  static Future<String> hashPin(String pin) async {
    final salt = _generateSecureBytes(_saltLength);
    return hashPinWithSalt(pin, salt);
  }

  static Future<String> hashPinWithSalt(String pin, Uint8List saltBytes) async {
    final key = await _authKdf.deriveKeyFromPassword(
      password: pin,
      nonce: saltBytes,
    );

    final hash = await key.extractBytes();

    return '${base64.encode(saltBytes)}:${base64.encode(hash)}';
  }

  static Future<bool> verifyPin(String pin, String stored) async {
    try {
      final parts = stored.split(':');
      if (parts.length != 2) return false;

      final salt = base64.decode(parts[0]);
      final expected = base64.decode(parts[1]);

      final key = await _authKdf.deriveKeyFromPassword(
        password: pin,
        nonce: salt,
      );

      final actual = await key.extractBytes();

      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  static Uint8List extractAuthSalt(String stored) {
    return base64.decode(stored.split(':')[0]);
  }

  static Future<Map<String, String>> wrapDeviceKey({
    required Uint8List authSaltBytes,
    required String password,
    required List<String> mnemonicWords,
  }) async {
    final String combinedSecret = '$password|${mnemonicWords.join(' ').trim().toLowerCase()}';
    final wrapSalt = _generateSecureBytes(_saltLength);
    final wrapNonce = _generateSecureBytes(_nonceLength);

    final wrapKey = await _encryptionKdf.deriveKeyFromPassword(
      password: combinedSecret,
      nonce: wrapSalt,
    );

    final secretBox = await _cipher.encrypt(
      authSaltBytes,
      secretKey: wrapKey,
      nonce: wrapNonce,
    );

    final macAndCipher = BytesBuilder()
      ..add(secretBox.mac.bytes)
      ..add(secretBox.cipherText);

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

      final wrapKey = await _encryptionKdf.deriveKeyFromPassword(
        password: combinedSecret,
        nonce: saltBytes,
      );

      final box = SecretBox(cipherBytes, nonce: nonceBytes, mac: Mac(macBytes));
      final clear = await _cipher.decrypt(box, secretKey: wrapKey);

      return Uint8List.fromList(clear);
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