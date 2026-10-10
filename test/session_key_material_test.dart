import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/domain_key_derivation.dart';
import 'package:Rocen/core/session_security_manager.dart';

/// SessionKeyMaterial's constructor is library-private (it is a `part of`
/// session_security_manager.dart) so a second owner cannot be instantiated.
/// Its behaviour is therefore verified through the only real path to it:
/// SessionSecurityManager.unlock -> install, and lockSync -> destroy.

Uint8List _candidate(int seed) => Uint8List.fromList(
    List<int>.generate(32, (i) => (seed * 31 + i * 7) & 0xFF));

Future<List<int>> _frozenNek(Uint8List mk) async {
  final k = await DomainKeyDerivation.deriveNoteEncryptionKey(mk);
  try {
    return List<int>.from(k.bytes);
  } finally {
    k.zero();
  }
}

Future<List<int>> _frozenTek(Uint8List mk) async {
  final k = await DomainKeyDerivation.deriveGithubTokenEncryptionKey(mk);
  try {
    return List<int>.from(k.bytes);
  } finally {
    k.zero();
  }
}

Future<void> _unlockWith(Uint8List candidate) =>
    SessionSecurityManager.instance.unlock(
      authenticate: () async => candidate,
      activateRoot: (_) async {},
      teardownRoot: () {},
    );

void main() {
  final ssm = SessionSecurityManager.instance;

  setUp(() {
    ssm.resetForTesting();
    ssm.finishBootstrap();
  });

  tearDown(() => ssm.lockSync());

  group('ownership transfer', () {
    test('the candidate buffer is consumed (zeroed) by the transfer', () async {
      final Uint8List mk = _candidate(1);
      await _unlockWith(mk);
      expect(mk, everyElement(0));
    });

    test('installed NEK/TEK are exactly the frozen Stage 4 derivation of the '
        'supplied MK (proves the right MK was installed)', () async {
      final Uint8List mk = _candidate(2);
      final Uint8List reference = Uint8List.fromList(mk);
      final List<int> wantNek = await _frozenNek(reference);
      final List<int> wantTek = await _frozenTek(reference);

      await _unlockWith(mk);

      expect(ssm.requireNoteEncryptionKey(), equals(wantNek));
      expect(ssm.requireGithubTokenEncryptionKey(), equals(wantTek));
      expect(wantNek, isNot(equals(wantTek)));
    });

    test('a wrong-length candidate is rejected, zeroed, and installs nothing',
        () async {
      final Uint8List bad = Uint8List.fromList(List<int>.filled(16, 0x11));
      await expectLater(_unlockWith(bad),
          throwsA(isA<SessionActivationException>()));
      expect(bad, everyElement(0));
      expect(ssm.state, SessionState.locked);
      expect(() => ssm.requireNoteEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
    });

    test('returned NEK/TEK are defensive copies, not aliases of internal state',
        () async {
      await _unlockWith(_candidate(3));
      final Uint8List a = ssm.requireNoteEncryptionKey();
      final Uint8List original = Uint8List.fromList(a);
      a.fillRange(0, a.length, 0xFF);
      expect(ssm.requireNoteEncryptionKey(), equals(original));

      final Uint8List t = ssm.requireGithubTokenEncryptionKey();
      final Uint8List tOriginal = Uint8List.fromList(t);
      t.fillRange(0, t.length, 0xFF);
      expect(ssm.requireGithubTokenEncryptionKey(), equals(tOriginal));
    });
  });

  group('destruction', () {
    test('lock makes NEK and TEK unreachable', () async {
      await _unlockWith(_candidate(4));
      ssm.lockSync();
      expect(() => ssm.requireNoteEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
      expect(() => ssm.requireGithubTokenEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
    });

    test('lock is idempotent', () async {
      await _unlockWith(_candidate(5));
      ssm.lockSync();
      expect(() => ssm.lockSync(), returnsNormally);
    });
  });

  group('one owner at a time', () {
    test('unlocking while already unlocked is refused and does not disturb '
        'the live session; the refused candidate is not retained', () async {
      final Uint8List first = _candidate(6);
      final Uint8List reference = Uint8List.fromList(first);
      final List<int> firstNek = await _frozenNek(reference);
      await _unlockWith(first);

      final Uint8List second = _candidate(7);
      await expectLater(_unlockWith(second), throwsStateError);
      // unlock() refuses before touching the candidate; the caller still owns
      // and must dispose of it. The live session is untouched.
      expect(ssm.requireNoteEncryptionKey(), equals(firstNek));
      second.fillRange(0, second.length, 0);
    });

    test('a new session after a lock gets distinct NEK/TEK and nothing of the '
        'old one', () async {
      await _unlockWith(_candidate(8));
      final Uint8List oldNek = ssm.requireNoteEncryptionKey();
      final Uint8List oldTek = ssm.requireGithubTokenEncryptionKey();
      ssm.lockSync();

      await _unlockWith(_candidate(9));
      expect(ssm.requireNoteEncryptionKey(), isNot(equals(oldNek)));
      expect(ssm.requireGithubTokenEncryptionKey(), isNot(equals(oldTek)));
    });

    test('re-unlocking with the SAME MK re-derives from a fresh candidate; '
        'nothing is restored from the previous session', () async {
      final Uint8List mk1 = _candidate(10);
      final List<int> nek1 = await _frozenNek(Uint8List.fromList(mk1));
      await _unlockWith(mk1);
      expect(ssm.requireNoteEncryptionKey(), equals(nek1));
      ssm.lockSync();
      expect(() => ssm.requireNoteEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));

      await _unlockWith(_candidate(10));
      expect(ssm.requireNoteEncryptionKey(), equals(nek1));
    });
  });
}
