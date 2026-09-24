import 'dart:convert';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Canonical encoding primitives for turning a user's password and recovery
/// mnemonic into a deterministic, unambiguous byte sequence suitable as KDF
/// input.
///
/// This module intentionally contains NO key derivation, NO Argon2id calls,
/// and NO wrapping/unwrapping logic. Its only job is: given a password
/// string and/or a mnemonic word list, produce the exact same bytes every
/// time, on every supported device, regardless of how the text was typed
/// or which Unicode input method produced it.
///
/// This is Stage 1 of the master-key architecture. Stages 2 and onward
/// (Master Key generation, Password-KEK/Recovery-KEK derivation, envelope
/// encryption) are NOT implemented here and must not be added to this file.
class CanonicalEncoding {
  CanonicalEncoding._();

  /// Fixed domain-separation string bound into the Recovery-KEK input.
  /// Never localized, never varied by build flavor - changing this value
  /// changes the derived Recovery-KEK for every user, so it must remain
  /// a stable, versioned constant, matching the crypto envelope's own
  /// versioning discipline.
  static const String recoveryKekDomain = 'rocen:v2:recovery-kek';

  /// Normalizes a raw password string for cryptographic use.
  ///
  /// Uses NFC (Canonical Decomposition, followed by Canonical Composition)
  /// so that two visually-identical passwords produced by different input
  /// methods or keyboards (e.g. a precomposed "é" vs. "e" + a combining
  /// acute accent) normalize to the byte-identical result.
  static String normalizePassword(String rawPassword) {
    return unorm.nfc(rawPassword);
  }

  /// Normalizes a raw recovery mnemonic for cryptographic use.
  ///
  /// The input is the mnemonic's individual words, in their original,
  /// generated order. This function:
  ///   1. Lowercases every word (BIP-39 wordlist words are already
  ///      lowercase; this step exists to tolerate a user re-typing the
  ///      phrase with unintended capitalization during recovery, not to
  ///      change the wordlist's own canonical casing).
  ///   2. Joins the words with a single ASCII space, matching how the
  ///      mnemonic is conventionally presented and re-entered.
  ///   3. Applies NFKD (Compatibility Decomposition) to the joined
  ///      sentence, matching BIP-39's own reference normalization
  ///      convention for mnemonic sentences.
  ///
  /// The lowercase step is applied BEFORE normalization, not after -
  /// order matters here, since normalizing first and lowercasing second
  /// could theoretically produce a different result for certain Unicode
  /// edge cases where case-folding and decomposition interact. The
  /// wordlist itself (see bip39.dart) contains only ASCII lowercase words,
  /// so this ordering has no practical effect on standard BIP-39 phrases,
  /// but is specified explicitly here so the behavior is deterministic
  /// and documented rather than incidental.
  static String normalizeMnemonic(List<String> mnemonicWords) {
    final String joined = mnemonicWords.map((w) => w.toLowerCase()).join(' ');
    return unorm.nfkd(joined);
  }

  /// Encodes a single field as a length-prefixed byte block:
  /// 4-byte big-endian unsigned length, followed by the field's own UTF-8
  /// bytes.
  ///
  /// Length-prefixing (rather than a delimiter byte such as 0x00) is used
  /// so that field boundaries are unambiguous regardless of what bytes the
  /// field's own content happens to contain - a delimiter-based scheme
  /// could theoretically be confused by a field containing that exact
  /// delimiter byte; a length prefix cannot be, since the boundary is
  /// determined by a count, not by scanning for a matching byte value.
  static Uint8List _lengthPrefixedUtf8(String value) {
    final Uint8List contentBytes = Uint8List.fromList(utf8.encode(value));
    final ByteData lengthHeader = ByteData(4)
      ..setUint32(0, contentBytes.length, Endian.big);
    final Uint8List result = Uint8List(4 + contentBytes.length);
    result.setRange(0, 4, lengthHeader.buffer.asUint8List());
    result.setRange(4, result.length, contentBytes);
    return result;
  }

  /// Builds the exact canonical byte sequence used as Argon2id input for
  /// Recovery-KEK derivation:
  ///
  ///   lengthPrefixed(normalizedPassword) ++
  ///   lengthPrefixed(normalizedMnemonic) ++
  ///   lengthPrefixed(recoveryKekDomain)
  ///
  /// Both [rawPassword] and [mnemonicWords] are normalized internally by
  /// this function - callers must pass the raw, as-typed/as-generated
  /// values, not pre-normalized ones, so that normalization always happens
  /// exactly once, in exactly one place, with no risk of a caller
  /// accidentally normalizing twice or skipping normalization entirely.
  ///
  /// This function performs ONLY canonical encoding. It does not derive
  /// any key, and the returned bytes are not, by themselves, a secret in
  /// any different sense than the password and mnemonic already were -
  /// this is purely a deterministic encoding step that a later stage's
  /// Argon2id call will consume as input.
  static Uint8List buildRecoveryKekInput({
    required String rawPassword,
    required List<String> mnemonicWords,
  }) {
    final String normalizedPassword = normalizePassword(rawPassword);
    final String normalizedMnemonic = normalizeMnemonic(mnemonicWords);

    final Uint8List passwordBlock = _lengthPrefixedUtf8(normalizedPassword);
    final Uint8List mnemonicBlock = _lengthPrefixedUtf8(normalizedMnemonic);
    final Uint8List domainBlock = _lengthPrefixedUtf8(recoveryKekDomain);

    final Uint8List result = Uint8List(
        passwordBlock.length + mnemonicBlock.length + domainBlock.length);
    int offset = 0;
    result.setRange(offset, offset + passwordBlock.length, passwordBlock);
    offset += passwordBlock.length;
    result.setRange(offset, offset + mnemonicBlock.length, mnemonicBlock);
    offset += mnemonicBlock.length;
    result.setRange(offset, offset + domainBlock.length, domainBlock);

    return result;
  }
}
