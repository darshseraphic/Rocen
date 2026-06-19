import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoEngine {
  // =========================
  // CONFIGURATION CONSTANTS
  // =========================

  static const int _version = 1;
  static const int _saltLength = 16;
  static const int _nonceLength = 12; // Standard AES-GCM nonce size
  static const int _macLength = 16;   // Standard AES-GCM MAC tag size

  static final AesGcm _cipher = AesGcm.with256bits();

  // Heavy Profile: Used ONLY for login PIN storage & verification (Slows brute-forcing)
  static final Argon2id _authKdf = Argon2id(
    memory: 19456,   // 19 MB (OWASP Baseline)
    iterations: 3,   // 3 Passes
    parallelism: 1,  // Fits standard single-thread execution environments
    hashLength: 32,
  );

  // Balanced Profile: Used for Data Encryption (Protects keys while maintaining UI responsiveness)
  static final Argon2id _encryptionKdf = Argon2id(
    memory: 12288,   // 12 MB
    iterations: 2,
    parallelism: 1,
    hashLength: 32,
  );

  // =========================
  // PUBLIC API: DATA ENCRYPTION
  // =========================

  /// Encrypts data using a PIN
  static Future<String> encryptProcess(String input, String pin) async {
    final inputBytes = utf8.encode(input);

    // Secure per-message random salt and nonce
    final salt = _generateSecureBytes(_saltLength);
    final nonce = _generateSecureBytes(_nonceLength);

    // Derive Data Encryption Key (DEK)
    final secretKey = await _encryptionKdf.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );

    // Encrypt payload using explicit nonce
    final secretBox = await _cipher.encrypt(
      inputBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    // Pack: [Version (1B)] + [Salt (16B)] + [Nonce (12B)] + [MAC (16B)] + [Ciphertext]
    final package = BytesBuilder()
      ..add([_version])
      ..add(salt)
      ..add(secretBox.nonce)
      ..add(secretBox.mac.bytes)
      ..add(secretBox.cipherText);

    return base64.encode(package.toBytes());
  }

  /// Decrypts data using a PIN
  static Future<String> decryptProcess(String input, String pin) async {
    try {
      final bytes = base64.decode(input);

      // Simple structural validation
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

      // Re-derive the identical Data Encryption Key
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

  // =========================
  // PUBLIC API: PIN AUTHENTICATION
  // =========================

  /// Hashes a user PIN securely for authentication/login checks
  static Future<String> hashPin(String pin) async {
    final salt = _generateSecureBytes(_saltLength);

    final key = await _authKdf.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );

    final hash = await key.extractBytes();

    return '${base64.encode(salt)}:${base64.encode(hash)}';
  }

  /// Verifies a login PIN attempt using constant-time evaluation
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

  // =========================
  // CORE INTERNAL HELPERS
  // =========================

  /// Generates cryptographically secure random bytes natively in a block allocation
  static Uint8List _generateSecureBytes(int length) {
    final rnd = Random.secure();
    final values = Uint8List(length);
    for (int i = 0; i < length; i++) {
      values[i] = rnd.nextInt(256);
    }
    return values;
  }

  /// Prevents timing attacks when comparing sensitive hash arrays
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;

    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}