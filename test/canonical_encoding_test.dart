import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/canonical_encoding.dart';

void main() {
  group('CanonicalEncoding.normalizePassword', () {
    // Test vector 1: composed vs. decomposed accented character.
    // "café" typed with a precomposed U+00E9 (é) vs. the same word typed
    // as "e" (U+0065) followed by a combining acute accent (U+0301).
    // Both must normalize to the identical NFC result - this is exactly
    // the cross-keyboard/cross-input-method scenario NFC exists to fix.
    test('composed and decomposed accented input normalize identically',
        () {
      const String composed = 'caf\u00E9'; // café, precomposed é
      const String decomposed = 'cafe\u0301'; // caf + e + combining acute

      final String normalizedComposed =
          CanonicalEncoding.normalizePassword(composed);
      final String normalizedDecomposed =
          CanonicalEncoding.normalizePassword(decomposed);

      expect(normalizedComposed, equals(normalizedDecomposed),
          reason:
              'NFC normalization must make these two byte-different but '
              'visually-identical inputs produce identical output, so the '
              'same real-world password typed on different input methods '
              'derives the same key.');

      // Also confirm the two RAW inputs actually differ before
      // normalization - otherwise this test would trivially pass for the
      // wrong reason (i.e. if the test vector itself were accidentally
      // already-identical).
      expect(composed, isNot(equals(decomposed)),
          reason:
              'Sanity check: the raw test inputs must differ at the byte '
              'level for this test to be meaningful.');
    });

    // Test vector 2: emoji with a variation selector.
    // Confirms NFC normalization handles a base character plus a
    // variation selector (U+FE0F) consistently and does not crash or
    // silently strip the selector in a way that would vary between runs.
    test('emoji with variation selector normalizes deterministically', () {
      const String withSelector = '\u2764\uFE0F'; // heavy black heart + VS16

      final String firstRun =
          CanonicalEncoding.normalizePassword(withSelector);
      final String secondRun =
          CanonicalEncoding.normalizePassword(withSelector);

      expect(firstRun, equals(secondRun),
          reason:
              'Normalizing the same input twice must always produce the '
              'same output - this is a determinism check specifically for '
              'a Unicode edge case (variation selectors) that some '
              'normalization implementations handle inconsistently.');
    });

    // Test vector 4 (from the design's numbered list - included here under
    // password normalization since it exercises the same function):
    // an empty password must not crash the normalizer or the encoder.
    test('empty password does not throw and normalizes to empty string',
        () {
      final String result = CanonicalEncoding.normalizePassword('');
      expect(result, equals(''));
    });

    // Test vector 5: right-to-left (RTL) text.
    // Confirms UTF-8 byte encoding (logical order), not any
    // display/visual-order transformation, is what ultimately feeds the
    // encoder - normalization itself must not reorder characters.
    test('RTL text normalizes without reordering characters', () {
      const String arabicWord = '\u0645\u0631\u062D\u0628\u0627'; // "مرحبا"

      final String normalized =
          CanonicalEncoding.normalizePassword(arabicWord);

      // NFC normalization of already-precomposed Arabic text should be a
      // no-op (Arabic script does not commonly involve the kind of
      // combining-character composition Latin scripts do for this word),
      // so the normalized form should equal the original logical-order
      // string - this test would catch an implementation that
      // accidentally reversed or reordered the string for "display"
      // purposes before encoding.
      expect(normalized, equals(arabicWord));
    });
  });

  group('CanonicalEncoding.normalizeMnemonic', () {
    // Test vector 3: mixed-case input vs. lowercase input must produce
    // identical normalized output, proving the lowercase step runs before
    // NFKD and is applied consistently regardless of how the user
    // re-typed the phrase.
    test('mixed-case and lowercase mnemonic input normalize identically',
        () {
      final List<String> mixedCase = [
        'Abandon',
        'Ability',
        'Able',
        'About',
        'Above',
        'Absent',
        'Absorb',
        'Abstract',
        'Absurd',
        'Abuse',
        'Access',
        'Accident',
      ];
      final List<String> allLowercase =
          mixedCase.map((w) => w.toLowerCase()).toList();

      final String normalizedMixed =
          CanonicalEncoding.normalizeMnemonic(mixedCase);
      final String normalizedLowercase =
          CanonicalEncoding.normalizeMnemonic(allLowercase);

      expect(normalizedMixed, equals(normalizedLowercase),
          reason:
              'A user re-typing their mnemonic with different '
              'capitalization must derive the identical Recovery-KEK '
              'input as the canonically-lowercase phrase.');
    });

    test('mnemonic words are joined with single ASCII spaces', () {
      final List<String> words = ['abandon', 'ability', 'able'];
      final String normalized = CanonicalEncoding.normalizeMnemonic(words);

      expect(normalized, equals('abandon ability able'));
    });
  });

  group('CanonicalEncoding.buildRecoveryKekInput - determinism', () {
    test('same password and mnemonic always produce identical bytes', () {
      const String password = 'correct horse battery staple';
      final List<String> mnemonic = [
        'abandon',
        'ability',
        'able',
        'about',
        'above',
        'absent',
        'absorb',
        'abstract',
        'absurd',
        'abuse',
        'access',
        'accident',
      ];

      final firstResult = CanonicalEncoding.buildRecoveryKekInput(
        rawPassword: password,
        mnemonicWords: mnemonic,
      );
      final secondResult = CanonicalEncoding.buildRecoveryKekInput(
        rawPassword: password,
        mnemonicWords: mnemonic,
      );

      expect(firstResult, equals(secondResult),
          reason:
              'The same credentials must produce byte-identical canonical '
              'encoding on every call, on every device, per the frozen '
              'design requirement.');
    });

    test('different passwords produce different canonical bytes', () {
      final List<String> mnemonic = List.filled(12, 'abandon');

      final resultA = CanonicalEncoding.buildRecoveryKekInput(
        rawPassword: 'passwordA',
        mnemonicWords: mnemonic,
      );
      final resultB = CanonicalEncoding.buildRecoveryKekInput(
        rawPassword: 'passwordB',
        mnemonicWords: mnemonic,
      );

      expect(resultA, isNot(equals(resultB)));
    });

    test(
        'password+mnemonic combination is not ambiguous across a field-length boundary',
        () {
      // This specifically tests the length-prefixing fix over a naive
      // concatenation scheme: "ab" + "c" and "a" + "bc" must NOT collide,
      // proving field boundaries are determined by an explicit length
      // count, not by scanning content.
      final resultShortPasswordLongMnemonic =
          CanonicalEncoding.buildRecoveryKekInput(
        rawPassword: 'ab',
        mnemonicWords: ['cabandon'], // starts with "c"
      );
      final resultLongPasswordShortMnemonic =
          CanonicalEncoding.buildRecoveryKekInput(
        rawPassword: 'abc',
        mnemonicWords: ['abandon'],
      );

      expect(resultShortPasswordLongMnemonic,
          isNot(equals(resultLongPasswordShortMnemonic)),
          reason:
              'Length-prefixed encoding must prevent two different '
              'password/mnemonic splits that happen to share the same '
              'concatenated character sequence from producing the same '
              'canonical bytes.');
    });

    test('domain string is present in the encoded output', () {
      final result = CanonicalEncoding.buildRecoveryKekInput(
        rawPassword: 'testpassword',
        mnemonicWords: ['abandon'],
      );

      final domainBytes = utf8.encode(CanonicalEncoding.recoveryKekDomain);
      // The domain block's content bytes must appear somewhere in the
      // final output (a coarse but useful smoke test that the domain
      // string is genuinely being included, not accidentally omitted).
      final resultList = result.toList();
      final domainList = domainBytes.toList();
      bool found = false;
      for (int i = 0; i <= resultList.length - domainList.length; i++) {
        if (resultList.sublist(i, i + domainList.length).toString() ==
            domainList.toString()) {
          found = true;
          break;
        }
      }
      expect(found, isTrue,
          reason:
              'The fixed domain-separation string must be present in the '
              'canonical encoding output.');
    });
  });
}
