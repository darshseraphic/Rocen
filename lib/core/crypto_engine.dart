import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoEngine {

  static const int _version = 1;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final AesGcm _cipher = AesGcm.with256bits();

  static final Argon2id _authKdf = Argon2id(
    memory: 19456,
    iterations: 3,
    parallelism: 1,
    hashLength: 32,
  );

  static final Argon2id _encryptionKdf = Argon2id(
    memory: 12288,
    iterations: 2,
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
    final remainder = bytes.sublist(1 + _saltLength);

    final cypherPackage = BytesBuilder()
      ..add(versionByte)
      ..add(remainder);

    return {
      'salt': base64.encode(salt),
      'cyphertext': base64.encode(cypherPackage.toBytes()),
    };
  }

  static String mergeFromBackup(String saltBase64, String cyphertextBase64) {
    final saltBytes = base64.decode(saltBase64);
    final cypherBytes = base64.decode(cyphertextBase64);

    final versionByte = cypherBytes.sublist(0, 1);
    final remainder = cypherBytes.sublist(1);

    final fullPackage = BytesBuilder()
      ..add(versionByte)
      ..add(saltBytes)
      ..add(remainder);

    return base64.encode(fullPackage.toBytes());
  }

  static Future<String> hashPin(String pin) async {
    final salt = _generateSecureBytes(_saltLength);

    final key = await _authKdf.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );

    final hash = await key.extractBytes();

    return '${base64.encode(salt)}:${base64.encode(hash)}';
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