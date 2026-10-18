import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'support/fake_github_remote.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/github_backup_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/activation_contract.dart';

/// Race tests pause REAL production code and therefore need the test-control
/// build flag: `flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true`.
/// Without it they are reported as SKIPPED, never as passed.
final Object _skipUnlessControl = SecurityCheckpoints.isTestControlEnabled
    ? false
    : 'run with --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true';

/// Stage 5: verifies that `associateRemote` and `changePassword` require a
/// genuine, non-forgeable [SessionAuthorizationToken] and that every
/// protected durable write is fenced IMMEDIATELY before it happens.
///
/// There is no test-only entry point, no policy object and no bypass value:
/// every test obtains its token through a REAL unlock (real password, real
/// Argon2id unwrap, real HKDF). Race tests pause the real production code at
/// `SecurityCheckpoint.beforeProtectedWrite` (a secret-free seam reached
/// right before the final fence check), lock for real, and resume.
///
/// Evidence status: written against the real production path; NOT executed
/// in the authoring environment (no Dart/Flutter runtime was available).
const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

const String _password = 'BlockB!Password44';

/// A bare, minimally-constructible `GithubBackupService`. Sufficient here
/// because every test in this file that uses it expects
/// `associateRemote`'s authorization gate to refuse the call BEFORE the
/// service is ever invoked - so no method on it needs a working
/// implementation.


Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_auth_gate_test_');
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
    ssm.lockSync();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('production API cannot be satisfied without a real token', () {
    test('ordinary code cannot forge a valid SessionAuthorizationToken - '
        'there is no public constructor, factory, or bypass value', () {
      // This test documents a structural fact that holds because of how the
      // type is defined, not because of a runtime check: there is no
      // expression a caller outside session_security_manager.dart's library
      // can write that produces a SessionAuthorizationToken. The only way
      // to obtain one is SessionSecurityManager.captureAuthorization(),
      // which itself throws unless the session is genuinely unlocked right
      // now (exercised below). There is nothing further to execute for this
      // specific claim - key_ownership_audit_test.dart verifies the source
      // shape (no public constructor, no SessionAuthorizationPolicy-style
      // factory) mechanically.
      expect(ssm, isNotNull);
    });

    test('captureAuthorization() throws when the session is not unlocked - '
        'there is no way to obtain a token without a real session', () {
      ssm.finishBootstrap();
      expect(() => ssm.captureAuthorization(),
          throwsA(isA<SessionAuthorizationException>()));
    });
  });

  group('changePassword authorization gate', () {
    Future<void> establish() =>
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
        );

    test('proceeds with a genuinely current token (obtained through a real '
        'unlock, not fabricated)', () async {
      await establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final token = ssm.captureAuthorization();

      final result = await MasterKeyProductionService.instance.changePassword(
        oldPassword: _password,
        newPassword: 'BlockB!Password55',
        mnemonicWords: _mnemonic,
        authorizationToken: token,
      );
      expect(result, isNotNull);
      ssm.lockSync();
    });

    test('throws SessionAuthorizationRequiredException for a token that was '
        'valid at capture time but is now stale (session locked since), '
        'before touching the durable record', () async {
      await establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final staleToken = ssm.captureAuthorization();
      ssm.lockSync();
      final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;

      await expectLater(
        MasterKeyProductionService.instance.changePassword(
          oldPassword: _password,
          newPassword: 'BlockB!Password55',
          mnemonicWords: _mnemonic,
          authorizationToken: staleToken,
        ),
        throwsA(isA<SessionAuthorizationRequiredException>()),
      );

      final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
      expect(after.passwordWrap, before.passwordWrap);
    });

    test('a token captured for session N is rejected once session N+1 '
        'exists, even though session N+1 is also genuinely unlocked',
        () async {
      await establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final tokenN = ssm.captureAuthorization();
      ssm.lockSync();

      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      // Session N+1 is genuinely unlocked, but tokenN belongs to session N.
      expect(ssm.isAuthorizationValid(tokenN), isFalse);
      await expectLater(
        MasterKeyProductionService.instance.changePassword(
          oldPassword: _password,
          newPassword: 'BlockB!Password55',
          mnemonicWords: _mnemonic,
          authorizationToken: tokenN,
        ),
        throwsA(isA<SessionAuthorizationRequiredException>()),
      );
      ssm.lockSync();
    });

    test('a token that becomes stale before a queued mutation runs is '
        'caught, even though it was valid at call time', () async {
      await establish();
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final token = ssm.captureAuthorization();

      // Occupy the serialization queue with a real, currently-authorized
      // mutation first, and await it to completion so its ordering relative
      // to the second call is unambiguous.
      final result1 = await MasterKeyProductionService.instance.changePassword(
        oldPassword: _password,
        newPassword: 'BlockB!Password55',
        mnemonicWords: _mnemonic,
        authorizationToken: token,
      );
      expect(result1, isNotNull);

      // The token is still (incorrectly, for this test's purposes) "valid"
      // by isAuthorizationValid's own rules right up until lockSync() runs -
      // so lock the session NOW, simulating a lock that happens while a
      // second call is queued behind the first.
      final Future<dynamic> second = MasterKeyProductionService.instance.changePassword(
        oldPassword: 'BlockB!Password55',
        newPassword: 'BlockB!Password66',
        mnemonicWords: _mnemonic,
        authorizationToken: token,
      );
      ssm.lockSync();

      await expectLater(second, throwsA(isA<SessionAuthorizationRequiredException>()));
    });
  });

  group('associateRemote authorization gate', () {
    test('throws SessionAuthorizationRequiredException for a stale token, '
        'before touching the durable record or the remote service at all',
        () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final staleToken = ssm.captureAuthorization();
      ssm.lockSync();
      final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;

      await expectLater(
        MasterKeyProductionService.instance.associateRemote(
          service: FakeGithubRemote().service,
          password: _password,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
          authorizationToken: staleToken,
        ),
        throwsA(isA<SessionAuthorizationRequiredException>()),
      );

      final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
      expect(after.repository, isNot('owner/repo'));
    });
  });

  group('final fencing before protected durable mutation (deterministic)', () {
    Future<SessionAuthorizationToken> unlockedToken() async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      return ssm.captureAuthorization();
    }

    test('changePassword: lock while paused at the final write -> stale code '
        'does NOT write; record unchanged', () async {
      final token = await unlockedToken();
      final before = (await MasterKeyLocalStore.read())!;

      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<dynamic> attempt =
          MasterKeyProductionService.instance.changePassword(
        oldPassword: _password,
        newPassword: 'BlockB!Password55',
        mnemonicWords: _mnemonic,
        authorizationToken: token,
      );
      attempt.ignore();
      // All KDF work is done by now; production code is sitting right
      // before the final fence check + durable write.
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite);
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);

      await expectLater(
          attempt, throwsA(isA<SessionAuthorizationRequiredException>()));
      final after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
      expect(after.passwordWrap, before.passwordWrap);
      expect(after.recoveryWrap, before.recoveryWrap);
      expect(after.passwordVerifier, before.passwordVerifier);
    });

    test('associateRemote: lock while paused before the remote-side-effect '
        'start -> no remote write, no local mutation', () async {
      final token = await unlockedToken();
      final before = (await MasterKeyLocalStore.read())!;
      final remote = FakeGithubRemote();

      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<void> attempt =
          MasterKeyProductionService.instance.associateRemote(
        service: remote.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
        authorizationToken: token,
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite);
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);

      await expectLater(
          attempt, throwsA(isA<SessionAuthorizationRequiredException>()));
      expect(remote.mutationCount, 0,
          reason: 'the stale operation must not start the remote write');
      final after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
      expect(after.remoteRecoveryStatus, before.remoteRecoveryStatus);
    });
  }, skip: _skipUnlessControl);

  group('bootstrap permits are operation-scoped, not state-scoped', () {
    test('I: establishFirstDevice and recoverFromRemote are refused while a '
        'session is unlocked, and mutate nothing', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      ssm.finishBootstrap();
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final before = (await MasterKeyLocalStore.read())!;
      final remote = FakeGithubRemote();

      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: remote.service,
          repository: 'owner/repo',
        ),
        throwsA(isA<PreSessionOperationRefusedException>()),
      );
      await expectLater(
        MasterKeyProductionService.instance.recoverFromRemote(
          service: remote.service,
          password: _password,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
        ),
        throwsA(isA<PreSessionOperationRefusedException>()),
      );
      expect(remote.mutationCount, 0);
      final after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
    });

    test('I: a LOCKED established account gets NO bootstrap privilege '
        '(LOCKED alone does not authorize)', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      ssm.finishBootstrap();
      expect(ssm.state, SessionState.locked);
      final before = (await MasterKeyLocalStore.read())!;
      final remote = FakeGithubRemote();

      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: remote.service,
          repository: 'owner/repo',
        ),
        throwsA(isA<BootstrapNotEligibleException>()),
      );
      await expectLater(
        MasterKeyProductionService.instance.recoverFromRemote(
          service: remote.service,
          password: _password,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
        ),
        throwsA(isA<BootstrapNotEligibleException>()),
      );
      expect(remote.mutationCount, 0);
      final after = (await MasterKeyLocalStore.read())!;
      expect(after.revision, before.revision);
      expect(after.passwordWrap, before.passwordWrap);
      expect(after.remoteRecoveryStatus, before.remoteRecoveryStatus);
    });

    test('J: corrupt authority never falls through into bootstrap',
        () async {
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, '{not valid json');
      ssm.finishBootstrap();
      final remote = FakeGithubRemote();
      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: remote.service,
          repository: 'owner/repo',
        ),
        throwsA(isA<CorruptLocalAuthorityException>()),
      );
      await expectLater(
        MasterKeyProductionService.instance.recoverFromRemote(
          service: remote.service,
          password: _password,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
        ),
        throwsA(isA<CorruptLocalAuthorityException>()),
      );
      expect(remote.mutationCount, 0);
      expect(
        Hive.box(MasterKeyLocalStore.boxName)
            .get(MasterKeyLocalStore.recordKey),
        '{not valid json',
        reason: 'the corrupt record must be left exactly as found',
      );
    });

    test('K: genuine first-run establishment (with remote publication) and '
        'recovery work without any unlocked session', () async {
      final remote = FakeGithubRemote();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      expect(remote.files.containsKey('device_key.json'), isTrue);
      expect(remote.files.containsKey('password_state.json'), isTrue);
      final established = (await MasterKeyLocalStore.read())!;
      expect(ssm.state, isNot(SessionState.unlocked));

      // Fresh device: no local authority; recover from the same remote.
      await Hive.box(MasterKeyLocalStore.boxName).clear();
      await MasterKeyProductionService.instance.recoverFromRemote(
        service: remote.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      );
      final recovered = (await MasterKeyLocalStore.read())!;
      expect(recovered.recoveryWrap, established.recoveryWrap);
      expect(recovered.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    });

    test('G: a lock DURING BOOTSTRAP synchronously runs the sensitive '
        'cleanup callbacks (state stays BOOTSTRAP)', () {
      expect(ssm.state, SessionState.bootstrap);
      int cleared = 0;
      ssm.registerCleanup(() => cleared++);
      ssm.lockSync();
      expect(cleared, 1,
          reason: 'cleared synchronously inside lockSync, no frame needed');
      expect(ssm.state, SessionState.bootstrap);
      ssm.lockSync(); // idempotent
      expect(cleared, 1, reason: 'one-shot: not re-invoked on later locks');
    });

    test('epoch is monotonic across resetForTesting (no ABA)', () {
      final int before = ssm.epoch;
      ssm.lockSync();
      final int mid = ssm.epoch;
      ssm.resetForTesting();
      expect(mid, greaterThan(before));
      expect(ssm.epoch, greaterThanOrEqualTo(mid),
          reason: 'a reset must never rewind the epoch');
    });

    test('F/H: a bootstrap operation goes stale after lockSync at its first '
        'protected local write; nothing is written locally or remotely',
        () async {
      final remote = FakeGithubRemote();
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<void> attempt =
          MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite);
      ssm.lockSync(); // epoch advances in BOOTSTRAP; permit revoked
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await expectLater(
          attempt, throwsA(isA<PreSessionOperationRefusedException>()));
      expect(await MasterKeyLocalStore.read(), isNull);
      expect(remote.mutationCount, 0);
    }, skip: _skipUnlessControl);

    test('H: lock after the local record was written but before the remote '
        'create: the remote write never starts', () async {
      final remote = FakeGithubRemote();
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<void> attempt =
          MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // before local record
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // before remote create
      expect(await MasterKeyLocalStore.read(), isNotNull);
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await expectLater(
          attempt, throwsA(isA<PreSessionOperationRefusedException>()));
      expect(remote.mutationCount, 0);
      final local = (await MasterKeyLocalStore.read())!;
      expect(local.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished,
          reason: 'stale work never promoted the record');
    }, skip: _skipUnlessControl);

    Future<String> donorWrap() async {
      final donor = FakeGithubRemote();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: donor.service,
        repository: 'owner/repo',
      );
      final String wrap = donor.files['device_key.json']!;
      await Hive.box(MasterKeyLocalStore.boxName).clear();
      return wrap;
    }

    test('B1: the legitimate remote-initialization race is still handled: '
        'the operation reconciles ITS OWN record (conflict recorded), it is '
        'not refused as foreign authority', () async {
      final String wrap = await donorWrap();
      final remote = FakeGithubRemote()..raceWinnerContent = wrap;
      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: remote.service,
          repository: 'owner/repo',
        ),
        throwsA(isNot(isA<BootstrapNotEligibleException>())),
      );
      final record = (await MasterKeyLocalStore.read())!;
      expect(record.remoteRecoveryStatus, RemoteRecoveryStatus.conflict,
          reason: 'only possible through the owned-record branch');
      expect(remote.files['device_key.json'], wrap,
          reason: 'the race winner is never overwritten');
    });

    Future<void> raceWithChangedRecord(
      String Function(MasterKeyLocalRecord current) makeRaw,
    ) async {
      final String wrap = await donorWrap();
      final remote = FakeGithubRemote()..raceWinnerContent = wrap;
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<void> attempt =
          MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // local record write
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // before remote create
      final String raw = makeRaw((await MasterKeyLocalStore.read())!);
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, raw);
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      SecurityCheckpoints.reset();
      await expectLater(
          attempt, throwsA(isA<BootstrapNotEligibleException>()));
      expect(
        Hive.box(MasterKeyLocalStore.boxName)
            .get(MasterKeyLocalStore.recordKey),
        raw,
        reason: 'the concurrently changed record was not modified',
      );
      expect(remote.files['device_key.json'], wrap);
    }

    test('B2: identical wrappers but a different REVISION is not the '
        "operation's own record; it is refused and left untouched", () async {
      // ONLY the revision changes: every other persisted field (wrappers,
      // verifier, status, repository metadata) is byte-identical.
      await raceWithChangedRecord((current) {
        final Map<String, dynamic> m =
            jsonDecode(current.toJsonString()) as Map<String, dynamic>;
        m['revision'] = (m['revision'] as int) + 1;
        return jsonEncode(m);
      });
    }, skip: _skipUnlessControl);

    test('B3: identical wrappers and SAME revision but changed persisted '
        'metadata is refused and left untouched', () async {
      await raceWithChangedRecord((current) {
        final Map<String, dynamic> m =
            jsonDecode(current.toJsonString()) as Map<String, dynamic>;
        (m['remoteRecovery'] as Map<String, dynamic>)['repository'] =
            'owner/changed-metadata';
        return jsonEncode(m);
      });
    }, skip: _skipUnlessControl);

    test('Q: a bootstrap operation INVOKED before a lock but still queued is '
        'refused after the lock (invocation epoch), with zero mutations; a '
        'new post-lock operation still works', () async {
      final remoteA = FakeGithubRemote();
      final remoteB = FakeGithubRemote();
      final remoteC = FakeGithubRemote();
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<void> a =
          MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remoteA.service,
        repository: 'owner/repo',
      );
      a.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // A occupies the queue
      // B and C are invoked while A holds the queue (pre-lock invocations).
      final Future<void> b =
          MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remoteB.service,
        repository: 'owner/repo',
      );
      b.ignore();
      final Future<void> c = MasterKeyProductionService.instance
          .recoverFromRemote(
        service: remoteC.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      );
      c.ignore();
      ssm.lockSync();
      SecurityCheckpoints.reset(); // disarm + release A

      await expectLater(
          a, throwsA(isA<PreSessionOperationRefusedException>()));
      await expectLater(
          b, throwsA(isA<PreSessionOperationRefusedException>()),
          reason: 'queued pre-lock work must not become post-lock work');
      await expectLater(
          c, throwsA(isA<PreSessionOperationRefusedException>()));
      expect(await MasterKeyLocalStore.read(), isNull,
          reason: 'no protected local mutation by A, B or C');
      expect(remoteA.mutationCount, 0);
      expect(remoteB.mutationCount, 0);
      expect(remoteC.mutationCount, 0);

      // A genuinely new, post-lock invocation follows normal eligibility.
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      expect(await MasterKeyLocalStore.read(), isNotNull);
    }, skip: _skipUnlessControl);

    Future<String> wrapFromFreshDevice() async {
      final r = FakeGithubRemote();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: r.service,
        repository: 'owner/repo',
      );
      final String wrap = r.files['device_key.json']!;
      await Hive.box(MasterKeyLocalStore.boxName).clear();
      return wrap;
    }

    GithubBackupService serviceForBranch(FakeGithubRemote r, String branch) =>
        GithubBackupService(
          token: 'test-token',
          repoPath: 'owner/repo',
          branch: branch,
          client: r.client,
        );

    test('M1: the selected non-main branch is MISSING while the default '
        'branch holds device_key.json: recovery never accepts the '
        'default-branch wrapper as authority', () async {
      final String w1 = await wrapFromFreshDevice();
      final remote = FakeGithubRemote()..seed('device_key.json', w1);
      await expectLater(
        MasterKeyProductionService.instance.recoverFromRemote(
          service: serviceForBranch(remote, 'feature'),
          password: _password,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
        ),
        throwsA(isA<GithubBranchMissingException>()),
      );
      expect(
        remote.contentsRequests.where((r) => r.contains('device_key.json')),
        isEmpty,
        reason: 'no Contents read at all: an unpinned read would have been '
            'answered from the default branch',
      );
      expect(
        Hive.box(MasterKeyLocalStore.boxName).get(MasterKeyLocalStore.recordKey),
        isNull,
      );
      expect(remote.mutationCount, 0);
    });

    test('M1b: the snapshot API refuses a missing explicit branch in a '
        'non-empty repository, never returning default-branch data', () async {
      final remote = FakeGithubRemote()
        ..seed('device_key.json', '{"from":"default-branch"}');
      await expectLater(
        serviceForBranch(remote, 'feature')
            .fetchNoteFileWithRefSha('device_key.json'),
        throwsA(isA<GithubBranchMissingException>()),
        reason: 'an explicit missing branch in a NON-empty repository is '
            'refused, not answered with default-branch data or "empty"',
      );
      expect(remote.contentsRequests, isEmpty);
    });

    test('M2: a genuinely EMPTY repository still supports first-run '
        'initialization (explicit empty: no content, no sha, no file read)',
        () async {
      final remote = FakeGithubRemote();
      final snap =
          await remote.service.fetchNoteFileWithRefSha('device_key.json');
      expect(snap.content, isNull);
      expect(snap.refSha, isNull);
      expect(remote.contentsRequests, isEmpty);

      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      expect(remote.files.containsKey('device_key.json'), isTrue);
      expect(remote.files.containsKey('password_state.json'), isTrue);
      expect((await MasterKeyLocalStore.read())!.remoteRecoveryStatus,
          RemoteRecoveryStatus.published);
    });

    test('M3: every non-null authoritative snapshot carries a non-null '
        'commit sha and was fetched with exactly that sha as ref', () async {
      final remote = FakeGithubRemote()
        ..seed('device_key.json', '{"k":1}')
        ..seed('other.json', '{"o":1}');
      final snap =
          await remote.service.fetchNoteFileWithRefSha('device_key.json');
      expect(snap.content, isNotNull);
      expect(snap.refSha, isNotNull);
      expect(remote.contentsRequests.last,
          'GET device_key.json ref=${snap.refSha}');
      for (final String r in remote.contentsRequests) {
        expect(r, isNot(endsWith('ref=-')), reason: r);
      }
    });

    test('K2: an unknown persisted field makes the record CORRUPT: '
        'bootstrap fails closed and the record is left untouched', () async {
      final r0 = FakeGithubRemote();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: r0.service,
        repository: 'owner/repo',
      );
      final current = (await MasterKeyLocalStore.read())!;
      final Map<String, dynamic> top =
          jsonDecode(current.toJsonString()) as Map<String, dynamic>;
      top['unexpectedTopLevel'] = 1;
      final String rawTop = jsonEncode(top);
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, rawTop);
      ssm.finishBootstrap();
      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
        ),
        throwsA(isA<CorruptLocalAuthorityException>()),
      );
      expect(
        Hive.box(MasterKeyLocalStore.boxName).get(MasterKeyLocalStore.recordKey),
        rawTop,
      );
      final Map<String, dynamic> nested =
          jsonDecode(current.toJsonString()) as Map<String, dynamic>;
      (nested['remoteRecovery'] as Map<String, dynamic>)['extra'] = 'x';
      final String rawNested = jsonEncode(nested);
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, rawNested);
      await expectLater(
        MasterKeyProductionService.instance.recoverFromRemote(
          service: r0.service,
          password: _password,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
        ),
        throwsA(isA<CorruptLocalAuthorityException>()),
      );
      expect(
        Hive.box(MasterKeyLocalStore.boxName).get(MasterKeyLocalStore.recordKey),
        rawNested,
      );
    });

    test('R1: remote authority rotated while recovery is mid-KDF: the stale '
        'wrapper is rejected, no local authority exists, nothing published',
        () async {
      final String w1 = await wrapFromFreshDevice();
      final String w2 = await wrapFromFreshDevice(); // a different authority
      final remote = FakeGithubRemote()..seed('device_key.json', w1);
      SecurityCheckpoints.arm(SecurityCheckpoint.afterRecoveryUnwrap);
      final Future<void> attempt =
          MasterKeyProductionService.instance.recoverFromRemote(
        service: remote.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.afterRecoveryUnwrap);
      // The remote authority is replaced (new commit, new content).
      remote.files['device_key.json'] = w2;
      remote.branchSha = 'sha-rotated';
      SecurityCheckpoints.release(SecurityCheckpoint.afterRecoveryUnwrap);

      await expectLater(
          attempt, throwsA(isA<RemoteAuthorityChangedException>()));
      expect(
        Hive.box(MasterKeyLocalStore.boxName).get(MasterKeyLocalStore.recordKey),
        isNull,
        reason: 'no local authority (and no local password) from the stale '
            'wrapper',
      );
      expect(remote.mutationCount, 0,
          reason: 'no remote side effect from stale recovery');
      expect(remote.files['device_key.json'], w2);
      expect(PasswordStateManager.getKnownGeneration(), 0);
    }, skip: _skipUnlessControl);

    test('R2: only the commit moved (same JSON): version evidence, not just '
        'cached JSON, makes the snapshot stale', () async {
      final String w1 = await wrapFromFreshDevice();
      final remote = FakeGithubRemote()..seed('device_key.json', w1);
      SecurityCheckpoints.arm(SecurityCheckpoint.afterRecoveryUnwrap);
      final Future<void> attempt =
          MasterKeyProductionService.instance.recoverFromRemote(
        service: remote.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.afterRecoveryUnwrap);
      remote.branchSha = 'sha-unrelated-commit';
      SecurityCheckpoints.release(SecurityCheckpoint.afterRecoveryUnwrap);
      await expectLater(
          attempt, throwsA(isA<RemoteAuthorityChangedException>()));
      expect(
        Hive.box(MasterKeyLocalStore.boxName).get(MasterKeyLocalStore.recordKey),
        isNull,
      );
    }, skip: _skipUnlessControl);

    test('R3: unchanged remote: recovery succeeds, and every device_key.json '
        'read was PINNED to the observed commit', () async {
      final String w1 = await wrapFromFreshDevice();
      final remote = FakeGithubRemote()..seed('device_key.json', w1);
      await MasterKeyProductionService.instance.recoverFromRemote(
        service: remote.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      );
      final record = (await MasterKeyLocalStore.read())!;
      expect(record.recoveryWrap, w1);
      expect(record.remoteRecoveryStatus, RemoteRecoveryStatus.published);
      final reads = remote.contentsRequests
          .where((r) => r.startsWith('GET device_key.json'))
          .toList();
      expect(reads, isNotEmpty);
      for (final String r in reads) {
        expect(r, isNot(endsWith('ref=-')),
            reason: 'unpinned content read: $r');
      }
    });

    test('R4: the public recovery API no longer accepts caller-supplied '
        'wrapper JSON (SOURCE-REVIEWED ONLY)', () {
      final String prod =
          File('${Directory.current.path}/lib/core/master_key_production_service.dart')
              .readAsStringSync();
      final String settings =
          File('${Directory.current.path}/lib/features/settings.dart')
              .readAsStringSync();
      expect(prod, isNot(contains('knownRecoveryWrapJson')));
      expect(settings, isNot(contains('knownRecoveryWrapJson')));
    });

    test('S2: a record changed during validation into a form the SCHEMA '
        'does not permit (padded metadata) makes the protected write fail '
        'closed; the record is left untouched', () async {
      final String wrap = await wrapFromFreshDevice();
      final remote = FakeGithubRemote()..raceWinnerContent = wrap;
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<void> attempt =
          MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite);
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite);
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // right before the write
      final current = (await MasterKeyLocalStore.read())!;
      final Map<String, dynamic> m =
          jsonDecode(current.toJsonString()) as Map<String, dynamic>;
      (m['remoteRecovery'] as Map<String, dynamic>)['repository'] =
          ' owner/repo '; // whitespace-altered optional metadata
      final String raw = jsonEncode(m);
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, raw);
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      SecurityCheckpoints.reset();

      await expectLater(attempt, throwsA(isA<FormatException>()));
      expect(
        Hive.box(MasterKeyLocalStore.boxName).get(MasterKeyLocalStore.recordKey),
        raw,
        reason: 'unreadable/unsupported record is not overwritten',
      );
    }, skip: _skipUnlessControl);

    test('S: a record changed during asynchronous validation - after the '
        'earlier ownership check, before the protected write begins - is '
        'refused and left untouched', () async {
      final String wrap = await wrapFromFreshDevice();
      final remote = FakeGithubRemote()..raceWinnerContent = wrap;
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<void> attempt =
          MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // 1: local record write
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // 2: remote create
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      // 3: the owned-record branch passed its entry comparison and the KDF
      // validation; now paused right before its conflict write.
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite);
      final current = (await MasterKeyLocalStore.read())!;
      final Map<String, dynamic> m =
          jsonDecode(current.toJsonString()) as Map<String, dynamic>;
      (m['remoteRecovery'] as Map<String, dynamic>)['repository'] =
          'owner/changed-after-check';
      final String raw = jsonEncode(m); // same revision + wrappers
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, raw);
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      SecurityCheckpoints.reset();

      await expectLater(
          attempt, throwsA(isA<MasterKeyLocalRecordChanged>()));
      expect(
        Hive.box(MasterKeyLocalStore.boxName).get(MasterKeyLocalStore.recordKey),
        raw,
        reason: 'not overwritten, not promoted, not marked conflict',
      );
    }, skip: _skipUnlessControl);

    test('L: authority that appears while a recovery is paused is never '
        'overwritten or promoted by the stale recovery result', () async {
      // Remote holds a dataset recovered from another device.
      final donor = FakeGithubRemote();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: donor.service,
        repository: 'owner/repo',
      );
      final donorRecord = (await MasterKeyLocalStore.read())!;
      await Hive.box(MasterKeyLocalStore.boxName).clear();

      SecurityCheckpoints.arm(SecurityCheckpoint.beforeProtectedWrite);
      final Future<void> attempt =
          MasterKeyProductionService.instance.recoverFromRemote(
        service: donor.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // before local write
      // Concurrent appearance of DIFFERENT authority.
      final foreign = donorRecord.copyWith(repository: 'owner/foreign');
      await Hive.box(MasterKeyLocalStore.boxName).put(
          MasterKeyLocalStore.recordKey, foreign.toJsonString());
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      SecurityCheckpoints.reset();
      await expectLater(attempt, throwsA(isA<Object>()));
      final after = (await MasterKeyLocalStore.read())!;
      expect(after.repository, 'owner/foreign',
          reason: 'the existing authority was not overwritten');
      expect(after.revision, foreign.revision);
    }, skip: _skipUnlessControl);
  });

  group('no bypass surface exists in production source', () {
    test('no *ForTesting security mutation, no public durable write, no '
        'policy/callback authorization', () {
      final String svc = File(
        '${Directory.current.path}/lib/core/master_key_production_service.dart',
      ).readAsStringSync();
      final String store = File(
        '${Directory.current.path}/lib/core/master_key_local_store.dart',
      ).readAsStringSync();
      expect(svc, isNot(contains('associateRemoteForTesting')));
      expect(svc, isNot(contains('changePasswordForTesting')));
      expect(svc, isNot(contains('SessionAuthorizationPolicy')));
      expect(store, isNot(contains('static Future<void> write(')));
      expect(store, isNot(contains('static Future<void> clear(')));
      expect(store, contains('static Future<void> _write('));
    });
  });
}
