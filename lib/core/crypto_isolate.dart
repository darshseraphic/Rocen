import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'secure_bytes.dart';

class CryptoIsolate {
  static Future<Map<String, Uint8List>> deriveAndEncrypt({
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

  static Future<Uint8List> deriveKeyBytes({
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
      final bytes = await secretKey.extractBytes();
      return Uint8List.fromList(bytes);
    });
  }
}
