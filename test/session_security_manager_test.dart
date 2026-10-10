import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/session_security_manager.dart';

/// A fresh candidate MK owned by the test (stands in for the transaction-local
/// buffer produced by SessionUnlockService.unlockWithPassword). MasterKeyManager
/// holds no key bytes any more, so there is nothing to establish there.
Uint8List _authoritativeMk(int seed) => Uint8List.fromList(
    List<int>.generate(32, (i) => (seed * 31 + i * 7) & 0xFF));

/// Records how many times teardown was invoked, and whether more than one
/// call happened concurrently/overlapping (it never should).
class _TeardownSpy {
  int calls = 0;
  void call() => calls++;
}

void main() {
  setUp(() {
    SessionSecurityManager.instance.resetForTesting();
  });

  group('bootstrap and basic transitions', () {
    test('starts in bootstrap', () {
      expect(SessionSecurityManager.instance.state, SessionState.bootstrap);
    });

    test('finishBootstrap moves to locked', () {
      SessionSecurityManager.instance.finishBootstrap();
      expect(SessionSecurityManager.instance.state, SessionState.locked);
    });

    test('finishBootstrap twice throws', () {
      SessionSecurityManager.instance.finishBootstrap();
      expect(
        () => SessionSecurityManager.instance.finishBootstrap(),
        throwsStateError,
      );
    });

    test('unlock from bootstrap (before finishBootstrap) throws', () async {
      _authoritativeMk(1);
      await expectLater(
        SessionSecurityManager.instance.unlock(
          authenticate: () async => _authoritativeMk(1),
          activateRoot: (_) async {},
          teardownRoot: () {},
        ),
        throwsStateError,
      );
    });
  });

  group('happy path unlock/lock', () {
    test('full unlock reaches UNLOCKED with a valid authorization token', () async {
      final Uint8List mk = _authoritativeMk(2);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();

      bool activated = false;
      await ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (capability) async {
          expect(ssm.isActivationCapabilityValid(capability), isTrue);
          activated = true;
        },
        teardownRoot: () {},
      );

      expect(activated, isTrue);
      expect(ssm.state, SessionState.unlocked);
      final token = ssm.captureAuthorization();
      expect(ssm.isAuthorizationValid(token), isTrue);
    });

    test('requireNoteEncryptionKey/requireGithubTokenEncryptionKey work once unlocked', () async {
      final Uint8List mk = _authoritativeMk(3);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      await ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );

      final nek = ssm.requireNoteEncryptionKey();
      final tek = ssm.requireGithubTokenEncryptionKey();
      expect(nek.length, 32);
      expect(tek.length, 32);
      expect(nek, isNot(equals(tek)));
    });

    test('requireNoteEncryptionKey throws before unlock', () {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      expect(
        () => ssm.requireNoteEncryptionKey(),
        throwsA(isA<SessionAuthorizationException>()),
      );
    });

    test('lockSync from unlocked returns to locked, invalidates token, advances epoch', () async {
      final Uint8List mk = _authoritativeMk(4);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      await ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      final token = ssm.captureAuthorization();
      final int epochBefore = ssm.epoch;

      ssm.lockSync();

      expect(ssm.state, SessionState.locked);
      expect(ssm.epoch, epochBefore + 1);
      expect(ssm.isAuthorizationValid(token), isFalse);
      expect(
        () => ssm.requireNoteEncryptionKey(),
        throwsA(isA<SessionAuthorizationException>()),
      );
    });

    test('lockSync calls teardownRoot exactly once', () async {
      final Uint8List mk = _authoritativeMk(5);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final spy = _TeardownSpy();
      await ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (_) async {},
        teardownRoot: spy.call,
      );

      ssm.lockSync();
      expect(spy.calls, 1);

      // Locking again (already locked) must not call teardown again.
      ssm.lockSync();
      expect(spy.calls, 1);
    });

    test('can unlock again after a lock, producing a fresh token/epoch', () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();

      final Uint8List mk1 = _authoritativeMk(6);
      await ssm.unlock(
        authenticate: () async => mk1,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      final token1 = ssm.captureAuthorization();
      ssm.lockSync();

      final Uint8List mk2 = _authoritativeMk(7);
      await ssm.unlock(
        authenticate: () async => mk2,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      final token2 = ssm.captureAuthorization();

      expect(ssm.state, SessionState.unlocked);
      expect(ssm.isAuthorizationValid(token1), isFalse);
      expect(ssm.isAuthorizationValid(token2), isTrue);
    });
  });

  group('rollback on failure', () {
    test('authentication failure rolls back to LOCKED, no keys, no commit', () async {
      _authoritativeMk(8);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final spy = _TeardownSpy();

      await expectLater(
        ssm.unlock(
          authenticate: () async => throw Exception('bad password'),
          activateRoot: (_) async {},
          teardownRoot: spy.call,
        ),
        throwsA(isA<SessionAuthenticationException>()),
      );

      expect(ssm.state, SessionState.locked);
      expect(
        () => ssm.requireNoteEncryptionKey(),
        throwsA(isA<SessionAuthorizationException>()),
      );
      // Authentication failure happens before ACTIVATING; teardown of a
      // root that was never constructed must not be invoked.
      expect(spy.calls, 0);
    });

    test('SessionAuthenticationException.cause preserves the original error', () async {
      _authoritativeMk(20);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final originalError = StateError('specific auth reason');

      try {
        await ssm.unlock(
          authenticate: () async => throw originalError,
          activateRoot: (_) async {},
          teardownRoot: () {},
        );
        fail('expected SessionAuthenticationException');
      } on SessionAuthenticationException catch (e) {
        expect(identical(e.cause, originalError), isTrue);
      }
    });

    test('activateRoot failure rolls back: keys destroyed, teardown called once', () async {
      final Uint8List mk = _authoritativeMk(9);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final spy = _TeardownSpy();

      await expectLater(
        ssm.unlock(
          authenticate: () async => mk,
          activateRoot: (_) async => throw Exception('root failed to mount'),
          teardownRoot: spy.call,
        ),
        throwsA(isA<SessionActivationException>()),
      );

      expect(ssm.state, SessionState.locked);
      expect(spy.calls, 1);
      expect(
        () => ssm.requireNoteEncryptionKey(),
        throwsA(isA<SessionAuthorizationException>()),
      );
    });

    test('lock during authenticate() discards the candidate key and rolls back', () async {
      final Uint8List mk = _authoritativeMk(10);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final spy = _TeardownSpy();

      final completer = Completer<Uint8List>();
      final unlockFuture = ssm.unlock(
        authenticate: () => completer.future,
        activateRoot: (_) async {},
        teardownRoot: spy.call,
      );

      // Simulate the app being locked (e.g. backgrounded) while the
      // authenticate() call (a slow password check) is still in flight.
      expect(ssm.state, SessionState.unlocking);
      ssm.lockSync();
      expect(ssm.state, SessionState.locked);

      // Now authentication "succeeds" late, after the lock already happened.
      completer.complete(mk);

      await expectLater(
        unlockFuture,
        throwsA(isA<SessionActivationException>()),
      );
      expect(ssm.state, SessionState.locked);
      // The late-arriving candidate key must never have been installed.
      expect(
        () => ssm.requireNoteEncryptionKey(),
        throwsA(isA<SessionAuthorizationException>()),
      );
    });

    test('lock during activateRoot() rolls back even if activateRoot never throws', () async {
      final Uint8List mk = _authoritativeMk(11);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final spy = _TeardownSpy();

      final completer = Completer<void>();
      final unlockFuture = ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (_) => completer.future,
        teardownRoot: spy.call,
      );

      // Let the microtask/timer queue advance so unlock() reaches ACTIVATING
      // and is suspended inside activateRoot(). pumpEventQueue drains
      // pending microtasks/timers repeatedly, which is more robust than a
      // single Future.delayed(Duration.zero) against this test becoming
      // flaky if intermediate async steps change shape later.
      await pumpEventQueue();
      expect(ssm.state, SessionState.activating);

      ssm.lockSync();
      expect(ssm.state, SessionState.locked);

      // activateRoot "succeeds" late, after the lock.
      completer.complete();

      await expectLater(
        unlockFuture,
        throwsA(isA<SessionActivationException>()),
      );
      expect(ssm.state, SessionState.locked);
      expect(spy.calls, 1);
      expect(
        () => ssm.requireNoteEncryptionKey(),
        throwsA(isA<SessionAuthorizationException>()),
      );
    });

    test('a stale authorization token from a rolled-back attempt is never minted', () async {
      final Uint8List mk = _authoritativeMk(12);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();

      await expectLater(
        ssm.unlock(
          authenticate: () async => mk,
          activateRoot: (_) async => throw Exception('boom'),
          teardownRoot: () {},
        ),
        throwsA(isA<SessionActivationException>()),
      );

      expect(
        () => ssm.captureAuthorization(),
        throwsA(isA<SessionAuthorizationException>()),
      );
    });
  });

  group('activation capability scoping', () {
    test('activation capability from one attempt is invalid after that attempt ends', () async {
      final Uint8List mk = _authoritativeMk(13);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();

      ActivationCapability? capturedCapability;
      await ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (capability) async {
          capturedCapability = capability;
        },
        teardownRoot: () {},
      );

      // Activation ended (committed) - the capability is no longer the
      // active one; capabilities are for the activation window only.
      expect(ssm.isActivationCapabilityValid(capturedCapability!), isFalse);
    });

    test('requireActivationCapabilityValid throws for a stale capability', () async {
      final Uint8List mk = _authoritativeMk(14);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();

      ActivationCapability? capturedCapability;
      await expectLater(
        ssm.unlock(
          authenticate: () async => mk,
          activateRoot: (capability) async {
            capturedCapability = capability;
            throw Exception('fail after capturing capability');
          },
          teardownRoot: () {},
        ),
        throwsA(isA<SessionActivationException>()),
      );

      expect(
        () => ssm.requireActivationCapabilityValid(capturedCapability!),
        throwsA(isA<SessionAuthorizationException>()),
      );
    });
  });

  group('cleanup registry', () {
    test('registered cleanup callbacks run on lockSync', () async {
      final Uint8List mk = _authoritativeMk(15);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      await ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );

      bool cleanupRan = false;
      ssm.registerCleanup(() => cleanupRan = true);
      ssm.lockSync();
      expect(cleanupRan, isTrue);
    });

    test('a throwing cleanup callback does not stop other callbacks or key destruction', () async {
      final Uint8List mk = _authoritativeMk(16);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      await ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );

      bool secondRan = false;
      ssm.registerCleanup(() => throw Exception('cleanup boom'));
      ssm.registerCleanup(() => secondRan = true);

      expect(() => ssm.lockSync(), returnsNormally);
      expect(secondRan, isTrue);
      expect(ssm.state, SessionState.locked);
    });

    test('unregister function removes the callback', () async {
      final Uint8List mk = _authoritativeMk(17);
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      await ssm.unlock(
        authenticate: () async => mk,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );

      bool ran = false;
      final unregister = ssm.registerCleanup(() => ran = true);
      unregister();
      ssm.lockSync();
      expect(ran, isFalse);
    });

    test('cleanup registry does not leak across sessions', () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();

      final Uint8List mk1 = _authoritativeMk(18);
      await ssm.unlock(
        authenticate: () async => mk1,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      int callCount = 0;
      ssm.registerCleanup(() => callCount++);
      ssm.lockSync();
      expect(callCount, 1);

      final Uint8List mk2 = _authoritativeMk(19);
      await ssm.unlock(
        authenticate: () async => mk2,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      ssm.lockSync();
      // The callback registered in the previous session must not fire
      // again for a later, unrelated lock.
      expect(callCount, 1);
    });
  });

  group('idempotency and never-throws guarantees', () {
    test('lockSync on a fresh bootstrap instance does not throw', () {
      expect(() => SessionSecurityManager.instance.lockSync(), returnsNormally);
    });

    test('lockSync called twice in a row from locked does not throw', () {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      expect(() => ssm.lockSync(), returnsNormally);
      expect(() => ssm.lockSync(), returnsNormally);
      expect(ssm.state, SessionState.locked);
    });

    test('no automatic unlock: lockSync never transitions to unlocked by itself', () {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      ssm.lockSync();
      expect(ssm.state, SessionState.locked);
    });
  });

  group('candidate MK ownership: zeroed on every path, never leaks forward', () {
    test('success: candidate is consumed (zeroed) by ownership transfer',
        () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final Uint8List candidate = _authoritativeMk(30);
      await ssm.unlock(
        authenticate: () async => candidate,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      expect(candidate, everyElement(0));
      expect(ssm.state, SessionState.unlocked);
    });

    test('stale epoch during authenticate: candidate zeroed, never installed',
        () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final Uint8List candidate = _authoritativeMk(31);
      final Completer<Uint8List> gate = Completer<Uint8List>();
      final Future<void> attempt = ssm.unlock(
        authenticate: () => gate.future,
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      ssm.lockSync();
      gate.complete(candidate);
      await expectLater(attempt, throwsA(isA<SessionActivationException>()));
      expect(candidate, everyElement(0));
      expect(() => ssm.requireNoteEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
    });

    test('activation failure: candidate zeroed and no key remains reachable',
        () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final Uint8List candidate = _authoritativeMk(32);
      await expectLater(
        ssm.unlock(
          authenticate: () async => candidate,
          activateRoot: (_) async => throw StateError('root failed'),
          teardownRoot: () {},
        ),
        throwsA(isA<SessionActivationException>()),
      );
      expect(candidate, everyElement(0));
      expect(() => ssm.requireNoteEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
      expect(() => ssm.requireGithubTokenEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
    });

    test('malformed candidate (wrong length): zeroed, rolled back to LOCKED',
        () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      final Uint8List bad = Uint8List.fromList(List<int>.filled(16, 0x55));
      await expectLater(
        ssm.unlock(
          authenticate: () async => bad,
          activateRoot: (_) async {},
          teardownRoot: () {},
        ),
        throwsA(isA<SessionActivationException>()),
      );
      expect(bad, everyElement(0));
      expect(ssm.state, SessionState.locked);
    });

    test('lock destroys NEK/TEK synchronously; nothing survives to LOCKED',
        () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      await ssm.unlock(
        authenticate: () async => _authoritativeMk(33),
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      expect(ssm.requireNoteEncryptionKey().length, 32);
      ssm.lockSync();
      expect(() => ssm.requireNoteEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
      expect(() => ssm.requireGithubTokenEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
    });

    test('double lock is safe and leaves no key material', () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();
      await ssm.unlock(
        authenticate: () async => _authoritativeMk(34),
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      ssm.lockSync();
      expect(() => ssm.lockSync(), returnsNormally);
      expect(() => ssm.requireNoteEncryptionKey(),
          throwsA(isA<SessionAuthorizationException>()));
    });

    test('second unlock: a new MK yields new NEK/TEK; the old token is dead',
        () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();

      await ssm.unlock(
        authenticate: () async => _authoritativeMk(35),
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      final firstNek = ssm.requireNoteEncryptionKey();
      final oldToken = ssm.captureAuthorization();
      ssm.lockSync();

      await ssm.unlock(
        authenticate: () async => _authoritativeMk(36),
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      expect(ssm.requireNoteEncryptionKey(), isNot(equals(firstNek)));
      expect(ssm.isAuthorizationValid(oldToken), isFalse);
    });
  });

  group('lock racing the activation transaction: outcome is interleaving-independent',
      () {
    // A lock can land at ANY await inside unlock(): during authenticate,
    // during NEK/TEK derivation inside install(), or during activateRoot.
    // Rather than depend on hitting one exact microtask, sweep the lock across
    // successive event-loop turns. Whatever the interleaving, the required
    // outcome is identical: never UNLOCKED, no key reachable, candidate zeroed.
    for (int turnsBeforeLock = 0; turnsBeforeLock <= 6; turnsBeforeLock++) {
      test('lock after $turnsBeforeLock event-loop turn(s)', () async {
        final ssm = SessionSecurityManager.instance;
        ssm.finishBootstrap();
        final Uint8List candidate = _authoritativeMk(40 + turnsBeforeLock);

        final Future<void> attempt = ssm.unlock(
          authenticate: () async => candidate,
          activateRoot: (_) async {
            await Future<void>.delayed(Duration.zero);
          },
          teardownRoot: () {},
        );

        for (int i = 0; i < turnsBeforeLock; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        ssm.lockSync();

        Object? error;
        try {
          await attempt;
        } catch (e) {
          error = e;
        }

        // If the lock landed after COMMIT the attempt legitimately succeeded
        // and lockSync then destroyed it; if before, it must have failed.
        // Either way the END STATE is the invariant.
        expect(ssm.state, SessionState.locked,
            reason: 'lock must always win (error: $error)');
        expect(() => ssm.requireNoteEncryptionKey(),
            throwsA(isA<SessionAuthorizationException>()));
        expect(() => ssm.requireGithubTokenEncryptionKey(),
            throwsA(isA<SessionAuthorizationException>()));
        expect(candidate, everyElement(0),
            reason: 'the candidate MK must never survive the transaction');
      });
    }

    test('a stale attempt can never authorize the NEXT session', () async {
      final ssm = SessionSecurityManager.instance;
      ssm.finishBootstrap();

      final Future<void> stale = ssm.unlock(
        authenticate: () async => _authoritativeMk(60),
        activateRoot: (_) async {
          await Future<void>.delayed(Duration.zero);
        },
        teardownRoot: () {},
      );
      ssm.lockSync();
      try {
        await stale;
      } catch (_) {}

      // Fresh, legitimate session afterwards.
      await ssm.unlock(
        authenticate: () async => _authoritativeMk(61),
        activateRoot: (_) async {},
        teardownRoot: () {},
      );
      expect(ssm.state, SessionState.unlocked);
      final token = ssm.captureAuthorization();
      expect(ssm.isAuthorizationValid(token), isTrue);
      expect(ssm.requireNoteEncryptionKey().length, 32);
    });
  });
}
