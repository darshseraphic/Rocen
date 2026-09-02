import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'secure_bytes.dart';

class CryptoIsolate {
  static Future<String> deriveKeyAsBase64({
    required String password,
    required Uint8List salt,
    required int memory,
    required int iterations,
  }) {
    return Isolate.run(() async {
      final kdf = Argon2id(
          memory: memory,
          iterations: iterations,
          parallelism: 1,
          hashLength: 32);
      final secretKey =
          await kdf.deriveKeyFromPassword(password: password, nonce: salt);
      final keyBytes =
          SecureBytes(Uint8List.fromList(await secretKey.extractBytes()));

      try {
        return base64.encode(keyBytes.bytes);
      } finally {
        keyBytes.zero();
      }
    });
  }

  static Future<bool> deriveKeyAndCompare({
    required String password,
    required Uint8List salt,
    required int memory,
    required int iterations,
    required Uint8List expected,
  }) {
    return Isolate.run(() async {
      final kdf = Argon2id(
          memory: memory,
          iterations: iterations,
          parallelism: 1,
          hashLength: 32);
      final secretKey =
          await kdf.deriveKeyFromPassword(password: password, nonce: salt);
      final keyBytes =
          SecureBytes(Uint8List.fromList(await secretKey.extractBytes()));
      final pinnedExpected = SecureBytes(expected);
      zeroBytes(expected);

      try {
        return _constantTimeEquals(keyBytes.bytes, pinnedExpected.bytes);
      } finally {
        keyBytes.zero();
        pinnedExpected.zero();
      }
    });
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;

    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  static Future<Map<String, Uint8List>?> deriveAndEncrypt({
    required Uint8List plaintext,
    required String password,
    required Uint8List salt,
    required Uint8List nonce,
    required int memory,
    required int iterations,
  }) {
    return Isolate.run(() async {
      final kdf = Argon2id(
          memory: memory,
          iterations: iterations,
          parallelism: 1,
          hashLength: 32);
      final secretKey =
          await kdf.deriveKeyFromPassword(password: password, nonce: salt);
      final keyBytes =
          SecureBytes(Uint8List.fromList(await secretKey.extractBytes()));

      try {
        final cipher = AesGcm.with256bits();
        final box = await cipher.encrypt(plaintext,
            secretKey: SecretKey(keyBytes.bytes), nonce: nonce);

        return {
          'cipherText': Uint8List.fromList(box.cipherText),
          'mac': Uint8List.fromList(box.mac.bytes),
        };
      } catch (_) {
        return null;
      } finally {
        keyBytes.zero();
      }
    });
  }

  static Future<Uint8List?> deriveAndDecrypt({
    required Uint8List cipherText,
    required Uint8List mac,
    required String password,
    required Uint8List salt,
    required Uint8List nonce,
    required int memory,
    required int iterations,
  }) {
    return Isolate.run(() async {
      final kdf = Argon2id(
          memory: memory,
          iterations: iterations,
          parallelism: 1,
          hashLength: 32);
      final secretKey =
          await kdf.deriveKeyFromPassword(password: password, nonce: salt);
      final keyBytes =
          SecureBytes(Uint8List.fromList(await secretKey.extractBytes()));

      try {
        final cipher = AesGcm.with256bits();
        final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
        final clear =
            await cipher.decrypt(box, secretKey: SecretKey(keyBytes.bytes));

        return Uint8List.fromList(clear);
      } catch (_) {
        return null;
      } finally {
        keyBytes.zero();
      }
    });
  }
}
