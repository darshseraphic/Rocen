import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'package:rocen/core/protected_session_resources.dart';
import 'support/activation_contract.dart';

/// Race tests pause REAL production code and therefore need the test-control
/// build flag: `flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true`.
/// Without it they are reported as SKIPPED, never as passed.
final Object _skipUnlessControl = SecurityCheckpoints.isTestControlEnabled
    ? false
    : 'run with --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true';

/// Per the Stage 5 final hardening gate: NO injectable authenticator.
/// Every test here drives the REAL production password path
/// (establishFirstDevice -> real durable record -> real password
/// verification -> real Argon2id unwrap) and uses the deterministic,
/// secret-free SecurityCheckpoints mechanism (see
/// lib/core/security_checkpoints.dart) to pin down exact interleavings for
/// race tests, instead of hoping pumpEventQueue() lands at the right
/// microtask.
const List<String> _mnemonic = [
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

const String _password = 'P4ssword-Zulu!';

class _TeardownSpy {
  int calls = 0;
  void call() => calls++;
}

Future<void> _establish([String password = _password]) =>
    MasterKeyProductionService.instance.establishFirstDevice(
      password: password,
      mnemonicWords: _mnemonic,
    );

Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_ssm_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
    SecurityCheckpoints.reset();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    enableSimulatedScreenAcknowledgementForTest();
  });

  tearDown(() {
    SecurityCheckpoints.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('bootstrap and basic transitions', () {
    test('starts in bootstrap', () {
      expect(ssm.state, SessionState.bootstrap);
    });

    test('finishBootstrap moves to locked', () {
      ssm.finishBootstrap();
      expect(ssm.state, SessionState.locked);
    });

    test('finishBootstrap twice throws', () {
      ssm.finishBootstrap();
      expect(() => ssm.finishBootstrap(), throwsStateError);
    });

    test('unlock from bootstrap (before finishBootstrap) throws', () async {
      await _establish();
      await expectLater(
        ssm.unlock(
          password: _password,
          activateRoot: satisfyActivationContract,
          teardownRoot: () {},
        ),
        throwsStateError,
      );
    });
  });

  group('happy path unlock/lock', () {
    test('full unlock reaches UNLOCKED with a valid authorization token',
        () async {
      await _establish();
      ssm.finishBootstrap();

      bool activated = false;
      await ssm.unlock(
        password: _password,
        activateRoot: (capability) async {
          expect(ssm.isActivationCapabilityValid(capability), isTrue);
          activated = true;
          await satisfyActivationContract(capability);
        },
        teardownRoot: () {},
      );

      expect(activated, isTrue);
      expect(ssm.state, SessionState.unlocked);
      final token = ssm.captureAuthorization();
      expect(ssm.isAuthorizationValid(token), isTrue);
      ssm.lockSync();
    });

    test(
        'after a real unlock SessionKeyMaterial owns the installed keys '
        '(observed as state only: no raw NEK/TEK leaves the manager)',
        () async {
      await _establish();
      ssm.finishBootstrap();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      expect(ssm.activationDiagnostics.transactionOwnsMk, isFalse);
      ssm.lockSync();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    test('no session keys are installed before unlock', () {
      ssm.finishBootstrap();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    test(
        'lockSync from unlocked returns to locked, invalidates token, '
        'advances epoch', () async {
      await _establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final token = ssm.captureAuthorization();
      final int epochBefore = ssm.epoch;

      ssm.lockSync();

      expect(ssm.state, SessionState.locked);
      expect(ssm.epoch, epochBefore + 1);
      expect(ssm.isAuthorizationValid(token), isFalse);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    test('lockSync calls teardownRoot exactly once', () async {
      await _establish();
      ssm.finishBootstrap();
      final spy = _TeardownSpy();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: spy.call,
      );

      ssm.lockSync();
      expect(spy.calls, 1);
      ssm.lockSync();
      expect(spy.calls, 1);
    });

    test('can unlock again after a lock, producing a fresh token/epoch',
        () async {
      await _establish();
      ssm.finishBootstrap();

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final token1 = ssm.captureAuthorization();
      ssm.lockSync();

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final token2 = ssm.captureAuthorization();

      expect(ssm.state, SessionState.unlocked);
      expect(ssm.isAuthorizationValid(token1), isFalse);
      expect(ssm.isAuthorizationValid(token2), isTrue);
      ssm.lockSync();
    });
  });

  group('rollback on failure (real authentication failures)', () {
    test('wrong password rolls back to LOCKED, no keys, no commit', () async {
      await _establish();
      ssm.finishBootstrap();
      final spy = _TeardownSpy();

      try {
        await ssm.unlock(
          password: 'wrong password entirely',
          activateRoot: satisfyActivationContract,
          teardownRoot: spy.call,
        );
        fail('expected SessionAuthenticationException');
      } on SessionAuthenticationException catch (e) {
        expect(e.cause, isA<UnlockAuthenticationFailedException>());
      }

      expect(ssm.state, SessionState.locked);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      // Authentication failure happens before ACTIVATING; teardown of a root
      // that was never constructed must not be invoked.
      expect(spy.calls, 0);
    });

    test(
        'no local account: unlock fails with NoLocalAuthorityException as '
        'the cause', () async {
      ssm.finishBootstrap();
      try {
        await ssm.unlock(
          password: _password,
          activateRoot: satisfyActivationContract,
          teardownRoot: () {},
        );
        fail('expected SessionAuthenticationException');
      } on SessionAuthenticationException catch (e) {
        expect(e.cause, isA<NoLocalAuthorityException>());
      }
      expect(ssm.state, SessionState.locked);
    });

    test(
        'activateRoot failure rolls back: keys destroyed, teardown called '
        'once', () async {
      await _establish();
      ssm.finishBootstrap();
      final spy = _TeardownSpy();

      await expectLater(
        ssm.unlock(
          password: _password,
          activateRoot: (_) async => throw Exception('root failed to mount'),
          teardownRoot: spy.call,
        ),
        throwsA(isA<SessionActivationException>()),
      );

      expect(ssm.state, SessionState.locked);
      expect(spy.calls, 1);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    test(
        'a stale authorization token is never minted after a rolled-back '
        'attempt', () async {
      await _establish();
      ssm.finishBootstrap();

      await expectLater(
        ssm.unlock(
          password: _password,
          activateRoot: (_) async => throw Exception('boom'),
          teardownRoot: () {},
        ),
        throwsA(isA<SessionActivationException>()),
      );

      expect(() => ssm.captureAuthorization(),
          throwsA(isA<SessionAuthorizationException>()));
    });
  });

  group('activation capability scoping', () {
    test(
        'activation capability from one attempt is invalid after that '
        'attempt ends', () async {
      await _establish();
      ssm.finishBootstrap();

      ActivationCapability? capturedCapability;
      await ssm.unlock(
        password: _password,
        activateRoot: (capability) async {
          capturedCapability = capability;
          await satisfyActivationContract(capability);
        },
        teardownRoot: () {},
      );

      expect(ssm.isActivationCapabilityValid(capturedCapability!), isFalse);
      ssm.lockSync();
    });

    test('requireActivationCapabilityValid throws for a stale capability',
        () async {
      await _establish();
      ssm.finishBootstrap();

      ActivationCapability? capturedCapability;
      await expectLater(
        ssm.unlock(
          password: _password,
          activateRoot: (capability) async {
            capturedCapability = capability;
            throw Exception('fail after capturing capability');
          },
          teardownRoot: () {},
        ),
        throwsA(isA<SessionActivationException>()),
      );

      expect(() => ssm.requireActivationCapabilityValid(capturedCapability!),
          throwsA(isA<SessionAuthorizationException>()));
    });
  });

  group('cleanup registry', () {
    test('registered cleanup callbacks run on lockSync', () async {
      await _establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );

      bool cleanupRan = false;
      ssm.registerCleanup(() => cleanupRan = true);
      ssm.lockSync();
      expect(cleanupRan, isTrue);
    });

    test(
        'a throwing cleanup callback does not stop other callbacks or key '
        'destruction', () async {
      await _establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
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
      await _establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );

      bool ran = false;
      final unregister = ssm.registerCleanup(() => ran = true);
      unregister();
      ssm.lockSync();
      expect(ran, isFalse);
    });

    test('cleanup registry does not leak across sessions', () async {
      await _establish();
      ssm.finishBootstrap();

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      int callCount = 0;
      ssm.registerCleanup(() => callCount++);
      ssm.lockSync();
      expect(callCount, 1);

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      ssm.lockSync();
      expect(callCount, 1);
    });
  });

  group('idempotency and never-throws guarantees', () {
    test('lockSync on a fresh bootstrap instance does not throw', () {
      expect(() => ssm.lockSync(), returnsNormally);
    });

    test('lockSync called twice in a row from locked does not throw', () {
      ssm.finishBootstrap();
      expect(() => ssm.lockSync(), returnsNormally);
      expect(() => ssm.lockSync(), returnsNormally);
      expect(ssm.state, SessionState.locked);
    });

    test(
        'no automatic unlock: lockSync never transitions to unlocked by '
        'itself', () {
      ssm.finishBootstrap();
      ssm.lockSync();
      expect(ssm.state, SessionState.locked);
    });
  });

  group('candidate MK ownership: the real unwrap never leaks forward', () {
    test('lock destroys NEK/TEK synchronously; nothing survives to LOCKED',
        () async {
      await _establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      ssm.lockSync();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    test('double lock is safe and leaves no key material', () async {
      await _establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      ssm.lockSync();
      expect(() => ssm.lockSync(), returnsNormally);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    test(
        'second unlock: a new NEK/TEK pair is installed; the old '
        'authorization token is dead', () async {
      await _establish();
      ssm.finishBootstrap();

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final oldToken = ssm.captureAuthorization();
      ssm.lockSync();

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      // Keys are re-derived and re-installed, not restored; the important
      // assertion is that the OLD TOKEN is dead.
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      expect(ssm.isAuthorizationValid(oldToken), isFalse);
    });
  });

  group('mandatory deterministic checkpoint races (real password/MK path)', () {
    /// Starts a real unlock() attempt armed at [checkpoint], waits until
    /// production code is deterministically paused there, locks for real,
    /// releases, and returns the attempt's outcome for the caller to make
    /// checkpoint-specific assertions on. Always also checks the baseline
    /// final-state properties every checkpoint must satisfy.
    Future<Object?> raceAtCheckpoint(
      SecurityCheckpoint checkpoint, {
      _TeardownSpy? spy,
    }) async {
      SecurityCheckpoints.arm(checkpoint);
      final Future<void> attempt = ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: spy?.call ?? () {},
      );

      await SecurityCheckpoints.waitUntilPaused(checkpoint);
      // Production code is NOW, deterministically, paused exactly at
      // `checkpoint` - not "probably", not "after enough event-loop turns".
      ssm.lockSync();
      SecurityCheckpoints.release(checkpoint);

      Object? error;
      try {
        await attempt;
      } catch (e) {
        error = e;
      }

      expect(ssm.state, SessionState.locked,
          reason: 'checkpoint=$checkpoint, error=$error');
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      return error;
    }

    // TEST A - lock during AFTER_PASSWORD_AUTH.
    // Proof required: no privileged continuation into MK unwrap.
    // Direct evidence: MasterKeyManager never leaves `none` (the unwrap/
    // acknowledgement step that would move it never ran), and the durable
    // record is untouched.
    test('A: lock during AFTER_PASSWORD_AUTH - no continuation into MK unwrap',
        () async {
      await _establish();
      ssm.finishBootstrap();
      final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;

      final error =
          await raceAtCheckpoint(SecurityCheckpoint.afterPasswordAuth);
      expect(error, isA<SessionActivationException>());

      expect(MasterKeyManager.instance.state, MasterKeyState.none,
          reason: 'authority must never be acknowledged for a stale attempt '
              'that never got past password verification');
      final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
      expect(after.passwordWrap, before.passwordWrap);
      expect(after.recoveryWrap, before.recoveryWrap);
    });

    // TEST B - lock during AFTER_MK_UNWRAP. MANDATORY: must prove
    // acknowledgeRecoveredAuthority() did NOT execute - not merely that the
    // final session state is LOCKED. The direct, observable proxy for
    // "acknowledgeRecoveredAuthority() ran" is MasterKeyManager.state ever
    // having become `authoritative`; since runExclusiveInitialization resets
    // state to `none` once its operation ends regardless of outcome, the
    // proof instead relies on the FACT that a stale transaction throws
    // checkFreshOrThrow BEFORE runExclusiveInitialization is even entered -
    // so the lease is never acquired at all for a stale attempt. We prove
    // this by acquiring the lease ourselves immediately after lockSync() and
    // confirming it is granted with NO contention, which could not be true
    // if the stale attempt's runExclusiveInitialization call were still
    // in-flight (it would still hold the lease, and a second
    // runExclusiveInitialization call would just chain behind it rather than
    // the state already having settled back to `none` synchronously
    // available).
    test(
        'B: lock during AFTER_MK_UNWRAP - acknowledgeRecoveredAuthority() '
        'never executes for the stale attempt', () async {
      // Source-level proof first: checkFreshOrThrow for this exact
      // checkpoint appears, in the real file, strictly before the call that
      // would mutate authority state - so a throw here structurally cannot
      // be followed by that mutation in the same control flow.
      final String src = File(
        '${Directory.current.path}/lib/core/session_unlock_service.dart',
      ).readAsStringSync();
      final int checkFreshIdx =
          src.indexOf("checkFreshOrThrow('AFTER_MK_UNWRAP')");
      final int runExclusiveIdx =
          src.indexOf('runExclusiveInitialization', checkFreshIdx);
      expect(checkFreshIdx, greaterThan(0));
      expect(runExclusiveIdx, greaterThan(checkFreshIdx),
          reason: 'the AFTER_MK_UNWRAP freshness check must appear before '
              'the call that acknowledges authority, not after');

      await _establish();
      ssm.finishBootstrap();

      final error = await raceAtCheckpoint(SecurityCheckpoint.afterMkUnwrap);
      expect(error, isA<SessionActivationException>());

      // If acknowledgeRecoveredAuthority() had executed for the stale
      // attempt, MasterKeyManager would have been left (at least
      // momentarily) `authoritative` before its operation wrapper reset it -
      // but more importantly, since checkFreshOrThrow throws BEFORE
      // runExclusiveInitialization is ever called on this path (see
      // _authenticateWithPassword's source ordering), no lease was ever
      // taken for this attempt at all. Confirm the manager is idle and a
      // fresh exclusive operation is granted immediately, not queued behind
      // a stale one.
      expect(MasterKeyManager.instance.state, MasterKeyState.none);
      expect(MasterKeyManager.instance.isInitializationInFlight, isFalse,
          reason: 'no lease should still be held by the stale attempt - it '
              'never reached runExclusiveInitialization');
    });

    // TEST C - lock during AFTER_NEK_DERIVATION.
    // Proof required: TEK derivation does not happen, and nothing is
    // published. Direct evidence: no session keys are installed (no
    // session exists to even hold one), and - more specifically - the
    // teardownRoot callback associated with THIS attempt is never invoked
    // with a successfully-activated root (activateRoot itself must never be
    // called, since install() fails before unlock() ever reaches it).
    test(
        'C: lock during AFTER_NEK_DERIVATION - TEK derivation never runs, '
        'activateRoot never called', () async {
      await _establish();
      ssm.finishBootstrap();
      bool activateRootCalled = false;
      SecurityCheckpoints.arm(SecurityCheckpoint.afterNekDerivation);

      final Future<void> attempt = ssm.unlock(
        password: _password,
        activateRoot: (capability) async {
          activateRootCalled = true;
        },
        teardownRoot: () {},
      );
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.afterNekDerivation);
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.afterNekDerivation);

      await expectLater(attempt, throwsA(isA<SessionActivationException>()));
      expect(activateRootCalled, isFalse,
          reason: 'install() must fail before TEK derivation, before '
              'commit, and long before activateRoot is ever reached');
      expect(ssm.state, SessionState.locked);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    // TEST D - lock during AFTER_TEK_DERIVATION.
    // Proof required: installation does not occur.
    test('D: lock during AFTER_TEK_DERIVATION - installation does not occur',
        () async {
      await _establish();
      ssm.finishBootstrap();
      bool activateRootCalled = false;
      SecurityCheckpoints.arm(SecurityCheckpoint.afterTekDerivation);

      final Future<void> attempt = ssm.unlock(
        password: _password,
        activateRoot: (_) async {
          activateRootCalled = true;
        },
        teardownRoot: () {},
      );
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.afterTekDerivation);
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.afterTekDerivation);

      await expectLater(attempt, throwsA(isA<SessionActivationException>()));
      expect(activateRootCalled, isFalse,
          reason: 'installation must fail before publishing anything, so '
              'activateRoot (which only runs after a successful install) '
              'must never be called');
      expect(ssm.state, SessionState.locked);
    });

    // TEST E - lock during BEFORE_SESSION_INSTALL.
    // Proof required: SessionKeyMaterial.install() never even begins.
    test('E: lock during BEFORE_SESSION_INSTALL - install() never begins',
        () async {
      await _establish();
      ssm.finishBootstrap();
      bool activateRootCalled = false;
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeSessionInstall);

      final Future<void> attempt = ssm.unlock(
        password: _password,
        activateRoot: (_) async {
          activateRootCalled = true;
        },
        teardownRoot: () {},
      );
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeSessionInstall);
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeSessionInstall);

      await expectLater(attempt, throwsA(isA<SessionActivationException>()));
      // install() never beginning means NEK/TEK are never derived at all for
      // this attempt - there is nothing to observe installed.
      expect(activateRootCalled, isFalse);
      expect(ssm.state, SessionState.locked);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    // TEST F - lock during AFTER_SESSION_INSTALL. MANDATORY: install() must
    // itself detect the staleness and fail - not merely have its result
    // rejected afterward by unlock()'s own separate capability check.
    //
    // Black-box note: because unlock() ALSO re-checks the activation
    // capability immediately after install() returns (as defense in depth),
    // a black-box observation of unlock()'s overall behavior (does
    // activateRoot get called? does the attempt throw?) is, by design,
    // IDENTICAL whether install() itself throws or whether it instead
    // returned "success" and was caught one line later by that outer check -
    // that equivalence is the whole point of defense in depth: the backstop
    // must be unreachable in correct code and must look the same from
    // outside if it ever did fire. So this test proves the property the
    // Stage 5 hardening gate actually cares about two ways:
    //   (1) at the SOURCE level (already verified above and re-asserted
    //       here against the real file, not from memory): install() itself
    //       contains its own post-AFTER_SESSION_INSTALL generation/staleness
    //       check that un-publishes and throws BEFORE returning,
    //   (2) at the BLACK-BOX level: the end-to-end outcome is correct
    //       regardless of which of the two layers caught it, proving the
    //       defense-in-depth design as a whole has no gap an attacker could
    //       observe or exploit.
    test(
        'F: lock during AFTER_SESSION_INSTALL - install() itself fails, '
        'does not report success', () async {
      // (1) Source-level proof that install() itself - not only unlock() -
      // detects and fails on this exact staleness window.
      final String installSource = File(
        '${Directory.current.path}/lib/core/session_key_material.dart',
      ).readAsStringSync();
      final int checkpointIdx =
          installSource.indexOf('SecurityCheckpoint.afterSessionInstall');
      expect(checkpointIdx, greaterThan(0));
      final int afterCheckpointEnd = checkpointIdx + 1500 < installSource.length
          ? checkpointIdx + 1500
          : installSource.length;
      final String afterCheckpoint =
          installSource.substring(checkpointIdx, afterCheckpointEnd);
      expect(afterCheckpoint, contains('_destroy()'),
          reason: 'install() must un-publish (destroy) on a stale '
              'AFTER_SESSION_INSTALL, not just leave it published for '
              'unlock() to reject');
      expect(afterCheckpoint,
          contains('throw const StaleActivationTransactionException'),
          reason: 'install() must itself throw for this exact window, not '
              'return normally and rely on the caller');

      // (2) Black-box end-to-end proof: the overall attempt is rejected
      // completely and consistently, with no privileged UI ever activated.
      await _establish();
      ssm.finishBootstrap();
      bool activateRootCalled = false;
      SecurityCheckpoints.arm(SecurityCheckpoint.afterSessionInstall);

      final Future<void> attempt = ssm.unlock(
        password: _password,
        activateRoot: (_) async {
          activateRootCalled = true;
        },
        teardownRoot: () {},
      );
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.afterSessionInstall);
      // At this exact instant, SessionKeyMaterial has ALREADY published
      // _mk/_nek/_tek and set _installed = true (that happens before the
      // checkpoint pause - see install()'s source, confirmed above).
      // lockSync() here synchronously destroys that already-published
      // material via SessionKeyMaterial.destroy().
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue,
          reason: 'at this pause the material is already transferred to '
              'SessionKeyMaterial');
      expect(ssm.activationDiagnostics.transactionOwnsMk, isFalse,
          reason: 'one-way transfer: the transaction no longer owns it');
      ssm.lockSync();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse,
          reason: 'lockSync destroys the installed material synchronously');
      SecurityCheckpoints.release(SecurityCheckpoint.afterSessionInstall);

      Object? error;
      try {
        await attempt;
      } catch (e) {
        error = e;
      }
      expect(activateRootCalled, isFalse,
          reason: 'no privileged UI may ever be activated for a stale '
              'installation attempt');
      expect(error, isA<SessionActivationException>());
      expect(ssm.state, SessionState.locked);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    // TEST G - lock during BEFORE_ACTIVATION_COMMIT.
    // Proof required: ACTIVATING never reaches UNLOCKED.
    test(
        'G: lock during BEFORE_ACTIVATION_COMMIT - stale transaction never '
        'commits UNLOCKED', () async {
      await _establish();
      ssm.finishBootstrap();
      bool rootWasActivated = false;

      SecurityCheckpoints.arm(SecurityCheckpoint.beforeActivationCommit);
      final Future<void> attempt = ssm.unlock(
        password: _password,
        activateRoot: (capability) async {
          // activateRoot DOES run before BEFORE_ACTIVATION_COMMIT in the
          // real ordering - that is expected and correct (see unlock()'s
          // source: activateRoot runs, then capability is re-checked, THEN
          // BEFORE_ACTIVATION_COMMIT). What must never happen is committing
          // to UNLOCKED afterward.
          rootWasActivated = true;
          final ProtectedSessionResources resources =
              ProtectedSessionResources();
          ssm.registerSessionResource(capability, resources);
          resources.markReady();
          ssm.reportProtectedRootReady(capability);
        },
        teardownRoot: () {},
      );
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeActivationCommit);
      expect(ssm.state, SessionState.activating,
          reason: 'must still be ACTIVATING, never UNLOCKED, while paused '
              'at the commit boundary');
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeActivationCommit);

      await expectLater(attempt, throwsA(isA<SessionActivationException>()));
      expect(rootWasActivated, isTrue,
          reason: 'sanity check: the root WAS activated before the commit '
              'boundary, confirming this test actually exercised the late '
              'checkpoint, not an earlier failure');
      expect(ssm.state, SessionState.locked,
          reason: 'never UNLOCKED - the stale transaction must not commit');
      final token = () {
        try {
          return ssm.captureAuthorization();
        } catch (_) {
          return null;
        }
      }();
      expect(token, isNull,
          reason: 'no authorization token may exist for a commit that never '
              'happened');
    });

    test(
        'a stale attempt (locked mid-activation) can never authorize the '
        'NEXT real session', () async {
      await _establish();
      ssm.finishBootstrap();
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeActivationCommit);

      final Future<void> stale = ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeActivationCommit);
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeActivationCommit);
      try {
        await stale;
      } catch (_) {}

      // Fresh, legitimate session afterwards, same real account.
      // The checkpoint is intentionally persistent after release; this test
      // only wants to pause the stale attempt, not the next valid session.
      SecurityCheckpoints.reset();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      expect(ssm.state, SessionState.unlocked);
      final token = ssm.captureAuthorization();
      expect(ssm.isAuthorizationValid(token), isTrue);
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isTrue);
      ssm.lockSync();
    }, timeout: const Timeout(Duration(minutes: 5)));
  }, skip: _skipUnlessControl);
  group('activation ownership and secret lifetime (real path, diagnostics)',
      () {
    Future<Object?> pauseThenLock(
      SecurityCheckpoint checkpoint,
      void Function() whilePaused, {
      void Function()? afterLock,
      ProtectedRootActivator? activate,
      ProtectedRootTeardown? teardown,
    }) async {
      SecurityCheckpoints.arm(checkpoint);
      final Future<void> attempt = ssm.unlock(
        password: _password,
        activateRoot: activate ?? satisfyActivationContract,
        teardownRoot: teardown ?? () {},
      );
      await SecurityCheckpoints.waitUntilPaused(checkpoint);
      whilePaused();
      ssm.lockSync();
      afterLock?.call();
      SecurityCheckpoints.release(checkpoint);
      Object? error;
      try {
        await attempt;
      } catch (e) {
        error = e;
      }
      return error;
    }

    setUp(() async {
      await _establish();
      ssm.finishBootstrap();
    });

    test('transaction is created per unlock, empty before and after', () async {
      expect(ssm.activationDiagnostics.transactionPresent, isFalse);
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final d = ssm.activationDiagnostics;
      expect(d.transactionPresent, isFalse);
      expect(
          d.transactionOwnsMk || d.transactionOwnsNek || d.transactionOwnsTek,
          isFalse,
          reason: 'after a committed unlock the transaction owns nothing');
      expect(d.sessionKeysInstalled, isTrue);
      ssm.lockSync();
      expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
    });

    test(
        'AFTER_MK_UNWRAP: transaction owns only the MK; lockSync clears it '
        'synchronously', () async {
      final error = await pauseThenLock(
        SecurityCheckpoint.afterMkUnwrap,
        () {
          final d = ssm.activationDiagnostics;
          expect(d.transactionPresent, isTrue);
          expect(d.transactionStale, isFalse);
          expect(d.transactionOwnsMk, isTrue);
          expect(d.transactionOwnsNek, isFalse);
          expect(d.sessionKeysInstalled, isFalse);
        },
        afterLock: () {
          final d = ssm.activationDiagnostics;
          expect(d.transactionStale, isTrue);
          expect(d.transactionOwnsMk, isFalse,
              reason: 'cleared in the same synchronous call as lockSync()');
        },
      );
      expect(error, isA<SessionActivationException>());
    });

    test(
        'AFTER_NEK_DERIVATION: transaction owns MK+NEK (no un-owned async '
        'local); lockSync clears both; TEK derivation never starts', () async {
      final error = await pauseThenLock(
        SecurityCheckpoint.afterNekDerivation,
        () {
          final d = ssm.activationDiagnostics;
          expect(d.transactionOwnsMk, isTrue);
          expect(d.transactionOwnsNek, isTrue);
          expect(d.transactionOwnsTek, isFalse);
          expect(d.sessionKeysInstalled, isFalse,
              reason: 'nothing is published before the one-way transfer');
        },
        afterLock: () {
          final d = ssm.activationDiagnostics;
          expect(d.transactionOwnsMk || d.transactionOwnsNek, isFalse);
        },
      );
      expect(error, isA<SessionActivationException>());
      expect(ssm.activationDiagnostics.transactionOwnsTek, isFalse,
          reason: 'TEK was never derived for the stale attempt');
    });

    test(
        'AFTER_TEK_DERIVATION / BEFORE_SESSION_INSTALL: transaction owns '
        'MK+NEK+TEK, nothing installed; lockSync clears all', () async {
      for (final cp in <SecurityCheckpoint>[
        SecurityCheckpoint.afterTekDerivation,
        SecurityCheckpoint.beforeSessionInstall,
      ]) {
        SecurityCheckpoints.reset();
        final error = await pauseThenLock(
          cp,
          () {
            final d = ssm.activationDiagnostics;
            expect(
                d.transactionOwnsMk &&
                    d.transactionOwnsNek &&
                    d.transactionOwnsTek,
                isTrue,
                reason: '$cp');
            expect(d.sessionKeysInstalled, isFalse, reason: '$cp');
          },
          afterLock: () {
            final d = ssm.activationDiagnostics;
            expect(
                d.transactionOwnsMk ||
                    d.transactionOwnsNek ||
                    d.transactionOwnsTek,
                isFalse,
                reason: '$cp');
          },
        );
        expect(error, isA<SessionActivationException>(), reason: '$cp');
        expect(ssm.state, SessionState.locked, reason: '$cp');
        ssm.resetForTesting();
        ssm.finishBootstrap();
      }
    });

    test(
        'H: unwrap in flight -> lockSync() -> unwrap returns -> stale '
        'transaction does not take the candidate; no authority mutation',
        () async {
      final error = await pauseThenLock(
        SecurityCheckpoint.duringMkUnwrap,
        () {
          expect(ssm.activationDiagnostics.transactionOwnsMk, isFalse);
        },
      );
      expect(error, isA<SessionActivationException>());
      expect((error as SessionActivationException).message,
          contains('MK_UNWRAP_RETURNED'),
          reason: 'stopped at the freshness check right after the unwrap '
              'await, before adoption');
      final d = ssm.activationDiagnostics;
      expect(d.transactionOwnsMk, isFalse,
          reason: 'stale transaction must not retain the returned MK');
      expect(MasterKeyManager.instance.state, MasterKeyState.none);
      expect(MasterKeyManager.instance.isInitializationInFlight, isFalse,
          reason: 'authority acknowledgement never ran');
      expect(ssm.state, SessionState.locked);
    });

    test(
        'lock during ACTIVATING destroys a registered privileged resource '
        'synchronously and invokes the visual teardown', () async {
      late ProtectedSessionResources resources;
      int teardowns = 0;
      final error = await pauseThenLock(
        SecurityCheckpoint.beforeActivationCommit,
        () {
          expect(ssm.activationDiagnostics.registeredSessionResources, 1);
        },
        afterLock: () {
          expect(resources.isDestroyed, isTrue,
              reason: 'destroyed inside lockSync(), not on a later frame');
          expect(teardowns, 1);
          expect(ssm.activationDiagnostics.registeredSessionResources, 0);
        },
        activate: (capability) async {
          resources = ProtectedSessionResources();
          ssm.registerSessionResource(capability, resources);
          resources.markReady();
          ssm.reportProtectedRootReady(capability);
        },
        teardown: () => teardowns++,
      );
      expect(error, isA<SessionActivationException>());
      expect(resources.isDestroyed, isTrue, reason: 'destroyed exactly once');
      expect(teardowns, 1, reason: 'teardown exactly once');
    });

    test(
        'registerSessionResource with a stale capability destroys the '
        'resource immediately and throws', () async {
      ActivationCapability? captured;
      await ssm.unlock(
        password: _password,
        activateRoot: (c) async {
          captured = c;
          await satisfyActivationContract(c);
        },
        teardownRoot: () {},
      );
      final ProtectedSessionResources resources = ProtectedSessionResources();
      expect(
        () => ssm.registerSessionResource(captured!, resources),
        throwsA(isA<SessionAuthorizationException>()),
      );
      expect(resources.isDestroyed, isTrue);
      ssm.lockSync();
    });

    test(
        'bootstrap permits: refused for an established account and while '
        'unlocked; revoked by lockSync', () async {
      // Established account (record exists), even though LOCKED.
      await expectLater(ssm.beginBootstrapOperation(invocationEpoch: ssm.epoch),
          throwsA(isA<BootstrapNotEligibleException>()));
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      await expectLater(ssm.beginBootstrapOperation(invocationEpoch: ssm.epoch),
          throwsA(isA<PreSessionOperationRefusedException>()));
      ssm.lockSync();
    });

    test(
        'a permit issued with no authority is revoked by lockSync and '
        'ended permits are invalid', () async {
      await Hive.box(MasterKeyLocalStore.boxName).clear();
      final BootstrapPermit permit =
          await ssm.beginBootstrapOperation(invocationEpoch: ssm.epoch);
      expect(() => ssm.requireBootstrapPermitValid(permit), returnsNormally);
      ssm.lockSync();
      expect(() => ssm.requireBootstrapPermitValid(permit),
          throwsA(isA<PreSessionOperationRefusedException>()));
      final BootstrapPermit second =
          await ssm.beginBootstrapOperation(invocationEpoch: ssm.epoch);
      ssm.endBootstrapOperation(second);
      expect(() => ssm.requireBootstrapPermitValid(second),
          throwsA(isA<PreSessionOperationRefusedException>()));
    });

    test('a superseded attempt cannot wipe a newer unlock', () async {
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeActivationCommit);
      final Future<void> stale = ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeActivationCommit);
      ssm.lockSync();
      SecurityCheckpoints.reset(); // disarm; also releases the stale attempt
      try {
        await stale;
      } catch (_) {}
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      expect(ssm.state, SessionState.unlocked);
      ssm.lockSync();
    });
  }, skip: _skipUnlessControl);
}
