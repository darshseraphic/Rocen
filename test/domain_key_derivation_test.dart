import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/domain_key_derivation.dart';
import 'package:Rocen/core/master_key_manager.dart';

Uint8List _masterKey(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed + i * 17) & 0xFF));

Future<List<int>> _deriveNotes(Uint8List mk) async {
  final key = await DomainKeyDerivation.deriveNoteEncryptionKey(mk);
  try {
    return List<int>.from(key.bytes);
  } finally {
    key.zero();
  }
}

Future<List<int>> _deriveToken(Uint8List mk) async {
  final key = await DomainKeyDerivation.deriveGithubTokenEncryptionKey(mk);
  try {
    return List<int>.from(key.bytes);
  } finally {
    key.zero();
  }
}

/// Stage 4 derivation is a pure function of caller-supplied Master Key bytes.
/// The HKDF construction, labels and key lengths are FROZEN - the test
/// vectors below are unchanged from before the Stage 5 ownership refactor
/// and prove that only the source of the input changed, not the contract.
void main() {
  group('Stage 4 - input validation (replaces the old manager-state gate)', () {
    test('a wrong-length key cannot derive NEK or TEK', () async {
      for (final int length in <int>[0, 16, 31, 33, 64]) {
        final Uint8List bad = Uint8List(length);
        await expectLater(
          DomainKeyDerivation.deriveNoteEncryptionKey(bad),
          throwsA(isA<DatasetNotInitializedException>()),
          reason: 'length $length must be rejected for NEK',
        );
        await expectLater(
          DomainKeyDerivation.deriveGithubTokenEncryptionKey(bad),
          throwsA(isA<DatasetNotInitializedException>()),
          reason: 'length $length must be rejected for TEK',
        );
      }
    });
  });

  group('Stage 4 - ownership: derivation never consumes or retains the input', () {
    test('the caller-supplied Master Key is not mutated or zeroed', () async {
      final Uint8List mk = _masterKey(3);
      final Uint8List before = Uint8List.fromList(mk);
      await _deriveNotes(mk);
      await _deriveToken(mk);
      expect(mk, equals(before));
    });

    test('zeroing the input afterwards does not affect an earlier result',
        () async {
      final Uint8List mk = _masterKey(5);
      final first = await _deriveNotes(mk);
      mk.fillRange(0, mk.length, 0);
      final Uint8List sameMkAgain = _masterKey(5);
      expect(await _deriveNotes(sameMkAgain), equals(first));
    });

    test('derivation does not touch MasterKeyManager state', () async {
      MasterKeyManager.instance.resetForTesting();
      await _deriveNotes(_masterKey(9));
      await _deriveToken(_masterKey(9));
      expect(MasterKeyManager.instance.state, MasterKeyState.none);
    });
  });

  group('Stage 4 - NEK/TEK derivation', () {
    test('a Master Key derives 256-bit NEK and TEK', () async {
      final mk = _masterKey(1);
      final noteKey = await DomainKeyDerivation.deriveNoteEncryptionKey(mk);
      final tokenKey =
          await DomainKeyDerivation.deriveGithubTokenEncryptionKey(mk);
      try {
        expect(noteKey.length, DomainKeyDerivation.keyLengthBytes);
        expect(tokenKey.length, DomainKeyDerivation.keyLengthBytes);
      } finally {
        noteKey.zero();
        tokenKey.zero();
      }
    });

    test('same MK + same domain is deterministic', () async {
      final mk = _masterKey(7);
      expect(await _deriveNotes(mk), equals(await _deriveNotes(mk)));
    });

    test('same MK + different domains produce different keys', () async {
      final mk = _masterKey(11);
      expect(await _deriveToken(mk), isNot(equals(await _deriveNotes(mk))),
          reason:
              'The notes and GitHub-token domains must never yield the same '
              'derived key from the same Master Key.');
    });

    test('different MKs produce different NEKs', () async {
      expect(await _deriveNotes(_masterKey(29)),
          isNot(equals(await _deriveNotes(_masterKey(13)))));
    });

    test('different MKs produce different TEKs', () async {
      expect(await _deriveToken(_masterKey(47)),
          isNot(equals(await _deriveToken(_masterKey(31)))));
    });
  });

  group('Stage 4 - frozen derivation contract', () {
    test('NEK and TEK are not interchangeable', () async {
      final mk = _masterKey(71);
      expect(await _deriveNotes(mk), isNot(equals(await _deriveToken(mk))));
    });

    test('NEK matches the frozen HKDF-SHA256 notes test vector', () async {
      final fixedMasterKey =
          Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(await _deriveNotes(fixedMasterKey), equals(<int>[
        0x8a, 0x3f, 0xd3, 0x89, 0xca, 0x5f, 0x6c, 0x9c,
        0x0a, 0x3f, 0xf6, 0xdd, 0x96, 0x96, 0x25, 0xd0,
        0x78, 0x4d, 0xa5, 0x86, 0xf6, 0xb5, 0x40, 0xe5,
        0x76, 0x93, 0x40, 0x00, 0x67, 0x46, 0x3b, 0xf3,
      ]));
    });

    test('TEK matches the frozen HKDF-SHA256 token test vector', () async {
      final fixedMasterKey =
          Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(await _deriveToken(fixedMasterKey), equals(<int>[
        0xcc, 0x34, 0x9c, 0xe9, 0x19, 0x33, 0x6c, 0x73,
        0xb1, 0x6a, 0x9f, 0xe1, 0xd2, 0x8e, 0x8d, 0x3b,
        0x53, 0xb1, 0xa3, 0x85, 0x60, 0xfe, 0x6b, 0x9b,
        0x78, 0xd4, 0x72, 0xbd, 0xaf, 0xad, 0x65, 0x00,
      ]));
    });
  });
}
