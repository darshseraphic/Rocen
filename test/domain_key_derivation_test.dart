import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/domain_key_derivation.dart';
import 'package:Rocen/core/master_key_manager.dart';

Uint8List _masterKey(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed + i * 17) & 0xFF));

Future<void> _installMasterKey(Uint8List key) =>
    MasterKeyManager.instance.runExclusiveInitialization<void>(
      (lease) async => MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(
        key,
        lease: lease,
      ),
    );

Future<List<int>> _deriveNotes() async {
  final key = await DomainKeyDerivation.deriveNoteEncryptionKey();
  try {
    return List<int>.from(key.bytes);
  } finally {
    key.zero();
  }
}

Future<List<int>> _deriveToken() async {
  final key = await DomainKeyDerivation.deriveGithubTokenEncryptionKey();
  try {
    return List<int>.from(key.bytes);
  } finally {
    key.zero();
  }
}

void main() {
  setUp(() {
    MasterKeyManager.instance.resetForTesting();
  });

  group('Stage 4 - authoritative MK gate', () {
    test('NONE cannot derive NEK or TEK', () async {
      await expectLater(
        DomainKeyDerivation.deriveNoteEncryptionKey(),
        throwsA(isA<DatasetNotInitializedException>()),
      );
      await expectLater(
        DomainKeyDerivation.deriveGithubTokenEncryptionKey(),
        throwsA(isA<DatasetNotInitializedException>()),
      );
    });

    test('PROVISIONAL cannot derive NEK or TEK', () async {
      MasterKeyManager.instance.generateProvisionalMasterKey();

      expect(MasterKeyManager.instance.state, MasterKeyState.provisional);
      await expectLater(
        DomainKeyDerivation.deriveNoteEncryptionKey(),
        throwsA(isA<DatasetNotInitializedException>()),
      );
      await expectLater(
        DomainKeyDerivation.deriveGithubTokenEncryptionKey(),
        throwsA(isA<DatasetNotInitializedException>()),
      );
    });
  });

  group('Stage 4 - NEK/TEK derivation', () {
    test('authoritative MK derives 256-bit NEK and TEK', () async {
      await _installMasterKey(_masterKey(1));

      final noteKey = await DomainKeyDerivation.deriveNoteEncryptionKey();
      final tokenKey =
          await DomainKeyDerivation.deriveGithubTokenEncryptionKey();
      try {
        expect(noteKey.length, DomainKeyDerivation.keyLengthBytes);
        expect(tokenKey.length, DomainKeyDerivation.keyLengthBytes);
      } finally {
        noteKey.zero();
        tokenKey.zero();
      }
    });

    test('same MK + same domain is deterministic', () async {
      await _installMasterKey(_masterKey(7));

      final first = await _deriveNotes();
      final second = await _deriveNotes();

      expect(second, equals(first));
    });

    test('same MK + different domains produce different keys', () async {
      await _installMasterKey(_masterKey(11));

      final nek = await _deriveNotes();
      final tek = await _deriveToken();

      expect(tek, isNot(equals(nek)),
          reason:
              'The notes and GitHub-token domains must never yield the same '
              'derived key from the same Master Key.');
    });

    test('different MKs produce different NEKs', () async {
      await _installMasterKey(_masterKey(13));
      final first = await _deriveNotes();

      MasterKeyManager.instance.resetForTesting();
      await _installMasterKey(_masterKey(29));
      final second = await _deriveNotes();

      expect(second, isNot(equals(first)));
    });

    test('different MKs produce different TEKs', () async {
      await _installMasterKey(_masterKey(31));
      final first = await _deriveToken();

      MasterKeyManager.instance.resetForTesting();
      await _installMasterKey(_masterKey(47));
      final second = await _deriveToken();

      expect(second, isNot(equals(first)));
    });
  });

  group('Stage 4 - frozen derivation contract', () {
    test('a fixed MK gives the same exact NEK after a session reset',
        () async {
      final mk = _masterKey(53);
      final secondMk = Uint8List.fromList(mk);
      await _installMasterKey(mk);
      final first = await _deriveNotes();

      MasterKeyManager.instance.resetForTesting();
      await _installMasterKey(secondMk);
      final second = await _deriveNotes();

      expect(second, equals(first));
    });

    test('NEK and TEK are not interchangeable', () async {
      await _installMasterKey(_masterKey(71));
      final nek = await _deriveNotes();
      final tek = await _deriveToken();

      expect(nek, isNot(equals(tek)),
          reason:
              'A note-encryption key must not be usable as the token-domain '
              'key, and vice versa.');
    });

    test('NEK matches the frozen HKDF-SHA256 notes test vector', () async {
      final fixedMasterKey = Uint8List.fromList(
          List<int>.generate(32, (i) => i));
      await _installMasterKey(fixedMasterKey);

      final nek = await _deriveNotes();

      expect(nek, equals(<int>[
        0x8a, 0x3f, 0xd3, 0x89, 0xca, 0x5f, 0x6c, 0x9c,
        0x0a, 0x3f, 0xf6, 0xdd, 0x96, 0x96, 0x25, 0xd0,
        0x78, 0x4d, 0xa5, 0x86, 0xf6, 0xb5, 0x40, 0xe5,
        0x76, 0x93, 0x40, 0x00, 0x67, 0x46, 0x3b, 0xf3,
      ]));
    });

    test('TEK matches the frozen HKDF-SHA256 token test vector', () async {
      final fixedMasterKey = Uint8List.fromList(
          List<int>.generate(32, (i) => i));
      await _installMasterKey(fixedMasterKey);

      final tek = await _deriveToken();

      expect(tek, equals(<int>[
        0xcc, 0x34, 0x9c, 0xe9, 0x19, 0x33, 0x6c, 0x73,
        0xb1, 0x6a, 0x9f, 0xe1, 0xd2, 0x8e, 0x8d, 0x3b,
        0x53, 0xb1, 0xa3, 0x85, 0x60, 0xfe, 0x6b, 0x9b,
        0x78, 0xd4, 0x72, 0xbd, 0xaf, 0xad, 0x65, 0x00,
      ]));
    });
  });
}
