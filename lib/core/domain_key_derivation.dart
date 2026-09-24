import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'master_key_manager.dart';
import 'secure_bytes.dart';

/// Stage 4: deterministic, domain-separated child keys derived from the
/// authoritative Master Key.
///
/// This class deliberately does NOT encrypt or decrypt application data.
/// Stage 6 owns the data-envelope format and will consume these keys.
///
/// Security invariants:
///   - The source key is obtained ONLY through
///     [MasterKeyManager.requireAuthoritativeMasterKeyBytes].
///   - No password, password verifier, mnemonic, or persisted secret is
///     involved in NEK/TEK derivation.
///   - NEK and TEK use distinct, fixed domain labels and therefore derive
///     independent-looking 256-bit keys from the same MK.
///   - Derived keys are returned as [SecureBytes] so callers have an explicit
///     lifetime/zeroization primitive rather than an ordinary String.
class DomainKeyDerivation {
  DomainKeyDerivation._();

  static const int keyLengthBytes = 32; // 256 bits

  /// Fixed domain labels are part of the v2 protocol contract. Do not change
  /// them without a deliberate protocol/version decision.
  static const String _notesInfo = 'rocen:v2:notes';
  static const String _githubTokenInfo = 'rocen:v2:github_token';

  /// HKDF-SHA256 with the frozen design's no-salt construction.
  ///
  /// RFC 5869 defines an omitted salt as HashLen zero bytes. We pass that
  /// representation explicitly instead of relying on package-specific empty
  /// nonce handling, preserving the protocol contract across cryptography
  /// package versions allowed by pubspec's `^2.7.0` constraint.
  static final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: keyLengthBytes,
  );

  /// Derives the Note Encryption Key (NEK) from the authoritative MK.
  ///
  /// Throws [DatasetNotInitializedException] when the MK is NONE/PROVISIONAL.
  static Future<SecureBytes> deriveNoteEncryptionKey() {
    return _deriveDomainKey(_notesInfo);
  }

  /// Derives the GitHub Token Encryption Key (TEK) from the authoritative MK.
  ///
  /// Throws [DatasetNotInitializedException] when the MK is NONE/PROVISIONAL.
  static Future<SecureBytes> deriveGithubTokenEncryptionKey() {
    return _deriveDomainKey(_githubTokenInfo);
  }

  static Future<SecureBytes> _deriveDomainKey(String info) async {
    // This is the single Stage-4 source of truth for MK access. In particular,
    // never add an overload that accepts arbitrary caller-supplied MK bytes.
    final Uint8List masterKeyBytes =
        MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();

    // Make a private copy before crossing into package:cryptography, then
    // release the copy in this method. The authoritative MK remains owned by
    // MasterKeyManager for the session.
    final Uint8List sourceCopy = Uint8List.fromList(masterKeyBytes);

    try {
      // Give the package-owned source SecretKeyData an explicitly zeroizable
      // backing buffer. We still zero sourceCopy separately because the
      // SecretKeyData constructor necessarily makes its own copy.
      final SecretKey sourceKey = SecretKeyData(
        sourceCopy,
        overwriteWhenDestroyed: true,
      );

      try {
        final SecretKeyData derivedKey = await _hkdf.deriveKey(
          secretKey: sourceKey,
          // Frozen v6 decision: MK is already uniform high-entropy material, so
          // HKDF uses the RFC 5869 no-salt representation: 32 zero bytes for
          // SHA-256. Domain separation lives in `info`.
          nonce: List<int>.filled(32, 0, growable: false),
          info: utf8.encode(info),
        );

        try {
          final List<int> derivedBytes = await derivedKey.extractBytes();

          try {
            if (derivedBytes.length != keyLengthBytes) {
              throw StateError(
                'HKDF returned ${derivedBytes.length} bytes; expected '
                '$keyLengthBytes bytes.',
              );
            }

            final Uint8List resultBytes = Uint8List.fromList(derivedBytes);
            try {
              return SecureBytes(resultBytes);
            } finally {
              zeroBytes(resultBytes);
            }
          } finally {
            // package:cryptography returns SensitiveBytes from extractBytes().
            // Its elements intentionally reject mutation, so release the
            // extracted view through its destruction API rather than writing
            // through operator[]=().
            if (derivedBytes is SensitiveBytes) {
              derivedBytes.destroy();
            }
          }
        } finally {
          // Release the package-owned derived SecretKeyData as soon as the
          // SecureBytes-owned copy has been created. Hkdf returns SecretKeyData
          // specifically so the key can be destroyed when no longer needed.
          derivedKey.destroy();
        }
      } finally {
        // This also zeroizes the temporary copy of the MK held by sourceKey.
        sourceKey.destroy();
      }
    } finally {
      zeroBytes(sourceCopy);
    }
  }

}
