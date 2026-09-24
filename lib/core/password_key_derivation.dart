import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'canonical_encoding.dart';
import 'crypto_isolate.dart';
import 'secure_bytes.dart';

/// Stage 3: password/recovery key derivation and Master Key wrapping.
///
/// SCOPE: Password-KEK, password verifier, Recovery-KEK, and wrapping/
/// unwrapping the Master Key under each. Deliberately NOT here:
/// HKDF/NEK/TEK (Stage 4), envelope v2 (Stage 6), session locking
/// (Stage 5), hardware wrapping (Stage 9).
///
/// Core invariants enforced by construction:
///   - The Master Key is NEVER derived from the password. It is only ever
///     wrapped/unwrapped. No function here takes a password and returns a
///     Master Key without also being given an existing wrapped blob.
///   - The password verifier is NEVER used as encryption/decryption key
///     material. It has its own salt and is only ever compared.
///   - A password change re-wraps the SAME Master Key. No note ciphertext
///     is touched.
class _DecodedWrap {
  final int memory;
  final int iterations;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;

  const _DecodedWrap({
    required this.memory,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });
}

class PasswordKeyDerivation {
  PasswordKeyDerivation._();

  static const int _saltLengthBytes = 16;
  static const int _nonceLengthBytes = 12;
  static const int _keyLengthBytes = 32;

  /// KDF cost parameters. Stage 3 records these explicitly in every wrap
  /// so a later unwrap never depends on current device state - this is
  /// the Finding 3C fix applied at the wrap layer, where it belongs.
  // Approved Stage 3 Argon2id profile. Remote wrapper metadata is accepted
  // only when it exactly matches this profile; no remote caller can request
  // an unbounded KDF cost.
  static const int defaultMemory = 65536;
  static const int defaultIterations = 3;

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => rnd.nextInt(256)));
  }

  // ---------------------------------------------------------------
  // Password verifier - authentication ONLY, never encryption material
  // ---------------------------------------------------------------

  /// Creates a password verifier record: `base64(salt):base64(hash)`.
  /// Uses a salt that is INDEPENDENT of every wrapping salt.
  static Future<String> createPasswordVerifier(String rawPassword) async {
    final salt = _randomBytes(_saltLengthBytes);
    final hashB64 = await CryptoIsolate.deriveKeyAsBase64(
      password: CanonicalEncoding.normalizePassword(rawPassword),
      salt: salt,
      memory: defaultMemory,
      iterations: defaultIterations,
    );
    return '${base64.encode(salt)}:$hashB64';
  }

  /// Verifies a password against a stored verifier record. Returns false
  /// on any malformation or mismatch - never throws, never leaks which
  /// part failed, and never returns key material of any kind.
  static Future<bool> verifyPassword(
      String rawPassword, String storedVerifier) async {
    try {
      if (!_isValidVerifierFormat(storedVerifier)) return false;
      final parts = storedVerifier.split(':');
      return await CryptoIsolate.deriveKeyAndCompare(
        password: CanonicalEncoding.normalizePassword(rawPassword),
        salt: Uint8List.fromList(base64.decode(parts[0])),
        memory: defaultMemory,
        iterations: defaultIterations,
        expected: Uint8List.fromList(base64.decode(parts[1])),
      );
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Wrapped Master Key envelope (Stage 3 wrap format)
  // ---------------------------------------------------------------

  /// Serializes a wrap as self-describing JSON. KDF parameters are stored
  /// explicitly so unwrapping never consults current device state.
  static String _encodeWrap({
    required Uint8List salt,
    required Uint8List nonce,
    required Uint8List cipherText,
    required Uint8List mac,
    required int memory,
    required int iterations,
  }) {
    return jsonEncode(<String, dynamic>{
      'v': 1,
      'kdf': 'argon2id',
      'memory': memory,
      'iterations': iterations,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'ct': base64.encode(cipherText),
      'mac': base64.encode(mac),
    });
  }

  static _DecodedWrap _decodeWrap(String wrapJson) {
    final decoded = jsonDecode(wrapJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('wrap is not a JSON object');
    }
    const requiredFields = [
      'v',
      'kdf',
      'memory',
      'iterations',
      'salt',
      'nonce',
      'ct',
      'mac',
    ];
    for (final String field in requiredFields) {
      if (!decoded.containsKey(field)) {
        throw FormatException('wrap is missing required field: $field');
      }
    }

    final dynamic version = decoded['v'];
    final dynamic kdf = decoded['kdf'];
    final dynamic memory = decoded['memory'];
    final dynamic iterations = decoded['iterations'];
    if (version is! int || version != 1) {
      throw FormatException('unsupported wrap version: $version');
    }
    if (kdf is! String || kdf != 'argon2id') {
      throw FormatException('unsupported KDF: $kdf');
    }
    if (memory is! int || memory != defaultMemory) {
      throw const FormatException('unsupported Argon2id memory profile');
    }
    if (iterations is! int || iterations != defaultIterations) {
      throw const FormatException('unsupported Argon2id iteration profile');
    }

    Uint8List? salt;
    Uint8List? nonce;
    Uint8List? cipherText;
    Uint8List? mac;
    try {
      salt = _decodeExactBase64(decoded['salt'], _saltLengthBytes, 'salt');
      nonce = _decodeExactBase64(decoded['nonce'], _nonceLengthBytes, 'nonce');
      cipherText = _decodeExactBase64(decoded['ct'], _keyLengthBytes, 'ct');
      mac = _decodeExactBase64(decoded['mac'], 16, 'mac');
      return _DecodedWrap(
        memory: memory,
        iterations: iterations,
        salt: salt,
        nonce: nonce,
        cipherText: cipherText,
        mac: mac,
      );
    } catch (_) {
      if (salt != null) zeroBytes(salt);
      if (nonce != null) zeroBytes(nonce);
      if (cipherText != null) zeroBytes(cipherText);
      if (mac != null) zeroBytes(mac);
      rethrow;
    }
  }

  static Uint8List _decodeExactBase64(
    dynamic raw,
    int expectedLength,
    String field,
  ) {
    if (raw is! String) {
      throw FormatException('$field must be a base64 string');
    }
    final int expectedEncodedLength = ((expectedLength + 2) ~/ 3) * 4;
    if (raw.length != expectedEncodedLength) {
      throw FormatException('$field has invalid encoded length');
    }
    Uint8List? decoded;
    try {
      decoded = Uint8List.fromList(base64.decode(raw));
      if (decoded.length != expectedLength) {
        throw FormatException('$field has invalid decoded length');
      }
      return decoded;
    } catch (_) {
      if (decoded != null) zeroBytes(decoded);
      throw FormatException('$field is not valid base64');
    }
  }

  static bool _isValidVerifierFormat(String storedVerifier) {
    final List<String> parts = storedVerifier.split(':');
    if (parts.length != 2) return false;
    Uint8List? salt;
    Uint8List? hash;
    try {
      salt = _decodeExactBase64(parts[0], _saltLengthBytes, 'verifier salt');
      hash = _decodeExactBase64(parts[1], _keyLengthBytes, 'verifier hash');
      return true;
    } catch (_) {
      return false;
    } finally {
      if (salt != null) zeroBytes(salt);
      if (hash != null) zeroBytes(hash);
    }
  }

  /// Wraps [masterKeyBytes] under a key derived from [derivationPassword]
  /// with a FRESH, independent salt. This is the single shared primitive
  /// behind both Password-KEK and Recovery-KEK wrapping - they differ only
  /// in what string is fed in as the derivation input, never in the
  /// wrapping mechanism itself.
  static Future<String> _wrapMasterKey({
    required Uint8List masterKeyBytes,
    required String derivationPassword,
    int memory = defaultMemory,
    int iterations = defaultIterations,
  }) async {
    if (masterKeyBytes.length != _keyLengthBytes) {
      throw ArgumentError('Master Key must be $_keyLengthBytes bytes.');
    }
    final salt = _randomBytes(_saltLengthBytes);
    final nonce = _randomBytes(_nonceLengthBytes);

    final result = await CryptoIsolate.deriveAndEncrypt(
      plaintext: masterKeyBytes,
      password: derivationPassword,
      salt: salt,
      nonce: nonce,
      memory: memory,
      iterations: iterations,
    );
    if (result == null) {
      throw StateError('Master Key wrapping failed.');
    }
    return _encodeWrap(
      salt: salt,
      nonce: nonce,
      cipherText: result['cipherText']!,
      mac: result['mac']!,
      memory: memory,
      iterations: iterations,
    );
  }

  /// Unwraps a Master Key. Returns null on ANY failure - wrong password,
  /// wrong mnemonic, corrupted wrap, or failed authentication tag. The
  /// caller cannot distinguish these, which is the correct fail-closed
  /// behavior: a wrong credential and a tampered blob are equally
  /// "you do not get the key."
  static Future<Uint8List?> _unwrapMasterKey({
    required String wrapJson,
    required String derivationPassword,
  }) async {
    try {
      final _DecodedWrap w = _decodeWrap(wrapJson);
      try {
        return await CryptoIsolate.deriveAndDecrypt(
          cipherText: w.cipherText,
          mac: w.mac,
          password: derivationPassword,
          salt: w.salt,
          nonce: w.nonce,
          memory: w.memory,
          iterations: w.iterations,
        );
      } finally {
        zeroBytes(w.salt);
        zeroBytes(w.nonce);
        zeroBytes(w.cipherText);
        zeroBytes(w.mac);
      }
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------
  // Password-KEK
  // ---------------------------------------------------------------

  /// Wraps the Master Key under a Password-KEK derived from the password
  /// alone, with its own fresh salt (independent of the verifier's salt).
  static Future<String> wrapMasterKeyWithPassword({
    required Uint8List masterKeyBytes,
    required String rawPassword,
  }) {
    return _wrapMasterKey(
      masterKeyBytes: masterKeyBytes,
      derivationPassword: CanonicalEncoding.normalizePassword(rawPassword),
    );
  }

  static Future<Uint8List?> unwrapMasterKeyWithPassword({
    required String wrapJson,
    required String rawPassword,
  }) {
    return _unwrapMasterKey(
      wrapJson: wrapJson,
      derivationPassword: CanonicalEncoding.normalizePassword(rawPassword),
    );
  }

  // ---------------------------------------------------------------
  // Recovery-KEK - BOTH password and mnemonic mandatory
  // ---------------------------------------------------------------

  /// Builds the Recovery-KEK derivation input from Stage 1's canonical
  /// encoding. Both factors are required parameters of this single call -
  /// there is no overload or code path producing a usable input from only
  /// one of them.
  ///
  /// The canonical bytes are base64-encoded purely as a lossless transport
  /// encoding, because CryptoIsolate's KDF entry points accept a String.
  /// This is NOT a security transformation: base64 is deterministic and
  /// reversible, so the full entropy and exact field-boundary structure of
  /// Stage 1's length-prefixed encoding is preserved intact.
  static String _recoveryDerivationInput({
    required String rawPassword,
    required List<String> mnemonicWords,
  }) {
    final canonicalBytes = CanonicalEncoding.buildRecoveryKekInput(
      rawPassword: rawPassword,
      mnemonicWords: mnemonicWords,
    );
    return base64.encode(canonicalBytes);
  }

  static Future<String> wrapMasterKeyWithRecovery({
    required Uint8List masterKeyBytes,
    required String rawPassword,
    required List<String> mnemonicWords,
  }) {
    return _wrapMasterKey(
      masterKeyBytes: masterKeyBytes,
      derivationPassword: _recoveryDerivationInput(
        rawPassword: rawPassword,
        mnemonicWords: mnemonicWords,
      ),
    );
  }

  static Future<Uint8List?> unwrapMasterKeyWithRecovery({
    required String wrapJson,
    required String rawPassword,
    required List<String> mnemonicWords,
  }) {
    return _unwrapMasterKey(
      wrapJson: wrapJson,
      derivationPassword: _recoveryDerivationInput(
        rawPassword: rawPassword,
        mnemonicWords: mnemonicWords,
      ),
    );
  }

  // ---------------------------------------------------------------
  // Password change - re-wrap only, including Recovery-KEK refresh
  // ---------------------------------------------------------------

  /// Re-wraps the SAME Master Key under a new password and refreshes the
  /// Recovery-KEK protection using the new password + mnemonic. Returns null
  /// if the old password or existing recovery credentials do not resolve to
  /// the same Master Key.
  ///
  /// Critically: this touches ONLY the Master Key wrappers and password
  /// verifier. No note or token ciphertext is read, re-encrypted, or even
  /// referenced.
  static Future<PasswordChangeResult?> changePassword({
    required String existingPasswordWrapJson,
    required String existingRecoveryWrapJson,
    required String oldRawPassword,
    required String newRawPassword,
    required List<String> mnemonicWords,
  }) async {
    final masterKey = await unwrapMasterKeyWithPassword(
      wrapJson: existingPasswordWrapJson,
      rawPassword: oldRawPassword,
    );
    if (masterKey == null) return null;

    // Verify that the existing Recovery-KEK wrapper resolves to the exact
    // same Master Key before rotating any wrapper. This prevents a malformed
    // or mismatched pair of persisted wrappers from silently becoming a
    // newly rotated, internally inconsistent set of artifacts.
    final existingRecoveryKey = await unwrapMasterKeyWithRecovery(
      wrapJson: existingRecoveryWrapJson,
      rawPassword: oldRawPassword,
      mnemonicWords: mnemonicWords,
    );
    if (existingRecoveryKey == null ||
        !_constantTimeEquals(masterKey, existingRecoveryKey)) {
      for (int i = 0; i < masterKey.length; i++) {
        masterKey[i] = 0;
      }
      if (existingRecoveryKey != null) {
        for (int i = 0; i < existingRecoveryKey.length; i++) {
          existingRecoveryKey[i] = 0;
        }
      }
      return null;
    }

    try {
      // The SAME MK is re-wrapped; it is never regenerated.
      final newPasswordWrap = await wrapMasterKeyWithPassword(
        masterKeyBytes: masterKey,
        rawPassword: newRawPassword,
      );
      final newRecoveryWrap = await wrapMasterKeyWithRecovery(
        masterKeyBytes: masterKey,
        rawPassword: newRawPassword,
        mnemonicWords: mnemonicWords,
      );
      final newVerifier = await createPasswordVerifier(newRawPassword);

      return PasswordChangeResult(
        newPasswordWrapJson: newPasswordWrap,
        newRecoveryWrapJson: newRecoveryWrap,
        newVerifier: newVerifier,
      );
    } finally {
      // The unwrapped MK copies are temporary plaintext key material.
      // Zero them as soon as this rotation operation is complete.
      for (int i = 0; i < masterKey.length; i++) {
        masterKey[i] = 0;
      }
      for (int i = 0; i < existingRecoveryKey.length; i++) {
        existingRecoveryKey[i] = 0;
      }
    }
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

/// Result of a successful password change. Note the absence of any note
/// or token data: a password change produces exactly three crypto artifacts.
class PasswordChangeResult {
  final String newPasswordWrapJson;
  final String newRecoveryWrapJson;
  final String newVerifier;

  const PasswordChangeResult({
    required this.newPasswordWrapJson,
    required this.newRecoveryWrapJson,
    required this.newVerifier,
  });
}
