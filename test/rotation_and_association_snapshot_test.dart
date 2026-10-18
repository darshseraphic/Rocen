import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/password_key_derivation.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/activation_contract.dart';
import 'support/fake_github_remote.dart';

/// Snapshot identity through the association decision and the rotation
/// publish. Needs the test-control define (resets and pause seams):
///   flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true
///
/// Honest scope: these tests change the remote BEFORE the final re-read. A
/// remote commit that lands after the last re-read and before the local write
/// cannot be detected - GitHub and Hive share no transaction.
///
/// Evidence: NOT executed in the authoring environment (no Dart/Flutter).
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
const String _p1 = 'BlockB!Password44';
const String _p2 = 'BlockB!Password55';

final Object _skipUnlessControl = SecurityCheckpoints.isTestControlEnabled
    ? false
    : 'run with --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true';

Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_snapshot_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    SecurityCheckpoints.reset();
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    ssm.finishBootstrap();
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

  Future<String> freshWrap() async {
    final r = FakeGithubRemote();
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: _p1,
      mnemonicWords: _mnemonic,
      remoteService: r.service,
      repository: 'owner/repo',
    );
    final String wrap = r.files['device_key.json']!;
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    return wrap;
  }

  Future<SessionAuthorizationToken> unlockToken(String password) async {
    ssm.lockSync();
    await ssm.unlock(
      password: password,
      activateRoot: satisfyActivationContract,
      teardownRoot: () {},
    );
    return ssm.captureAuthorization();
  }

  /// Local account that has PUBLISHED to [remote], then changed its password
  /// locally: unpublished + previousPublishedRecoveryWrap = the remote wrapper.
  Future<MasterKeyLocalRecord> pendingRotation(FakeGithubRemote remote) async {
    await MasterKeyProductionService.instance.establishFirstDevice(
      password: _p1,
      mnemonicWords: _mnemonic,
      remoteService: remote.service,
      repository: 'owner/repo',
    );
    final token = await unlockToken(_p1);
    await MasterKeyProductionService.instance.changePassword(
      oldPassword: _p1,
      newPassword: _p2,
      mnemonicWords: _mnemonic,
      authorizationToken: token,
    );
    ssm.lockSync();
    final local = (await MasterKeyLocalStore.read())!;
    expect(local.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished);
    expect(local.previousPublishedRecoveryWrap, isNotNull);
    return local;
  }

  group('rotation: device_key.json is part of the SAME pinned snapshot', () {
    test(
        'R-A: the wrapper changes (same passwordGeneration) between the '
        "association's observation and the rotation snapshot: the newer "
        'wrapper is not overwritten, no rotation commit, no local marker',
        () async {
      final String w2 = await freshWrap();
      final remote = FakeGithubRemote();
      final MasterKeyLocalRecord before = await pendingRotation(remote);
      final int mutationsBefore = remote.mutationCount;
      final String stateBefore = remote.files['password_state.json']!;
      final token = await unlockToken(_p2);

      SecurityCheckpoints.arm(SecurityCheckpoint.beforeRotationSnapshot);
      final Future<void> attempt =
          MasterKeyProductionService.instance.associateRemote(
        service: remote.service,
        password: _p2,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
        authorizationToken: token,
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeRotationSnapshot);
      // Another writer replaces device_key.json; passwordGeneration unchanged.
      remote.files['device_key.json'] = w2;
      remote.branchSha = 'e' * 40;
      SecurityCheckpoints.release(SecurityCheckpoint.beforeRotationSnapshot);

      await expectLater(
          attempt, throwsA(isA<RemoteAuthorityChangedException>()));
      expect(remote.files['device_key.json'], w2,
          reason: 'the newer wrapper was NOT overwritten');
      expect(remote.mutationCount, mutationsBefore,
          reason: 'no rotation commit was issued');
      expect(remote.files['password_state.json'], stateBefore);
      final after = (await MasterKeyLocalStore.read())!;
      expect(after.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished,
          reason: 'not falsely declared published, not moved to conflict');
      expect(after.revision, before.revision,
          reason: 'no local marker was written');
      expect(after.previousPublishedRecoveryWrap,
          before.previousPublishedRecoveryWrap);
    },
        skip: _skipUnlessControl,
        timeout: const Timeout(Duration(minutes: 5)));

    test(
        'R-B: the SAME rule on the race-recovery route (GithubFileAlready'
        'Exists): a wrapper changed before the rotation snapshot is refused',
        () async {
      final String w2 = await freshWrap();
      final first = FakeGithubRemote();
      final MasterKeyLocalRecord before = await pendingRotation(first);
      final String publishedWrap = before.previousPublishedRecoveryWrap!;
      final String stateJson = first.files['password_state.json']!;

      // A second repository: empty at first observation; the create then
      // loses a race to the previously published wrapper.
      final remote = FakeGithubRemote()..raceWinnerContent = publishedWrap;
      final token = await unlockToken(_p2);
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeRotationSnapshot);
      final Future<void> attempt =
          MasterKeyProductionService.instance.associateRemote(
        service: remote.service,
        password: _p2,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
        authorizationToken: token,
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeRotationSnapshot);
      remote.files['password_state.json'] = stateJson; // state now exists
      remote.files['device_key.json'] = w2; // ... and the wrapper changed
      remote.branchSha = 'd' * 40;
      final int mutationsAtPause = remote.mutationCount;
      SecurityCheckpoints.release(SecurityCheckpoint.beforeRotationSnapshot);

      await expectLater(
          attempt, throwsA(isA<RemoteAuthorityChangedException>()));
      expect(remote.files['device_key.json'], w2);
      expect(remote.mutationCount, mutationsAtPause,
          reason: 'no rotation commit');
      final after = (await MasterKeyLocalStore.read())!;
      expect(after.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished);
      expect(after.revision, before.revision);
    },
        skip: _skipUnlessControl,
        timeout: const Timeout(Duration(minutes: 5)));

    test(
        'R-C (control): an UNCHANGED wrapper rotates normally on the '
        'race-recovery route', () async {
      final first = FakeGithubRemote();
      final MasterKeyLocalRecord before = await pendingRotation(first);
      final String publishedWrap = before.previousPublishedRecoveryWrap!;
      final String stateJson = first.files['password_state.json']!;
      final remote = FakeGithubRemote()..raceWinnerContent = publishedWrap;
      final token = await unlockToken(_p2);
      SecurityCheckpoints.arm(SecurityCheckpoint.beforeRotationSnapshot);
      final Future<void> attempt =
          MasterKeyProductionService.instance.associateRemote(
        service: remote.service,
        password: _p2,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
        authorizationToken: token,
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeRotationSnapshot);
      remote.files['password_state.json'] = stateJson;
      remote.branchSha = 'c' * 40;
      SecurityCheckpoints.release(SecurityCheckpoint.beforeRotationSnapshot);
      SecurityCheckpoints.reset();
      await attempt;
      expect(remote.files['device_key.json'], before.recoveryWrap);
      expect((await MasterKeyLocalStore.read())!.remoteRecoveryStatus,
          RemoteRecoveryStatus.published);
    },
        skip: _skipUnlessControl,
        timeout: const Timeout(Duration(minutes: 5)));
  });

  group(
      'association KDF: the observed remote authority is re-validated '
      'before any protected local status write', () {
    Future<void> runKdfRace({required bool raceRoute}) async {
      final String wOther = await freshWrap();
      final String w3 = await freshWrap();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _p1,
        mnemonicWords: _mnemonic,
      );
      final MasterKeyLocalRecord before = (await MasterKeyLocalStore.read())!;
      final token = await unlockToken(_p1);

      final FakeGithubRemote remote = raceRoute
          ? (FakeGithubRemote()..raceWinnerContent = wOther)
          : (FakeGithubRemote()..seed('device_key.json', wOther));
      SecurityCheckpoints.arm(SecurityCheckpoint.afterAssociationKdf);
      final Future<void> attempt =
          MasterKeyProductionService.instance.associateRemote(
        service: remote.service,
        password: _p1,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
        authorizationToken: token,
      );
      attempt.ignore();
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.afterAssociationKdf);
      // The remote authority is rotated DURING the association KDF.
      remote.files['device_key.json'] = w3;
      remote.branchSha = 'b' * 40;
      final int mutationsAtPause = remote.mutationCount;
      SecurityCheckpoints.release(SecurityCheckpoint.afterAssociationKdf);

      await expectLater(
          attempt, throwsA(isA<RemoteAuthorityChangedException>()));
      expect(remote.files['device_key.json'], w3,
          reason: 'the new remote wrapper was not overwritten');
      expect(remote.mutationCount, mutationsAtPause);
      final after = (await MasterKeyLocalStore.read())!;
      expect(after.remoteRecoveryStatus, RemoteRecoveryStatus.unpublished,
          reason: 'neither published nor conflict was recorded from the '
              'stale snapshot');
      expect(after.revision, before.revision);
      expect(after.previousPublishedRecoveryWrap,
          before.previousPublishedRecoveryWrap);
    }

    test(
        'K-A: remote wrapper rotated during the KDF (existing-remote '
        'route): no status write',
        () => runKdfRace(raceRoute: false),
        skip: _skipUnlessControl,
        timeout: const Timeout(Duration(minutes: 5)));

    test(
        'K-B: remote wrapper rotated during the KDF (race-recovery '
        'route): no status write',
        () => runKdfRace(raceRoute: true),
        skip: _skipUnlessControl,
        timeout: const Timeout(Duration(minutes: 5)));

    test(
        'K-C (control): an unchanged but DIFFERENT-MK wrapper is recorded '
        'as a conflict (existing behaviour preserved)', () async {
      final String wOther = await freshWrap();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _p1,
        mnemonicWords: _mnemonic,
      );
      final token = await unlockToken(_p1);
      final remote = FakeGithubRemote()..seed('device_key.json', wOther);
      await expectLater(
        MasterKeyProductionService.instance.associateRemote(
          service: remote.service,
          password: _p1,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
          authorizationToken: token,
        ),
        throwsStateError,
      );
      expect((await MasterKeyLocalStore.read())!.remoteRecoveryStatus,
          RemoteRecoveryStatus.conflict);
      expect(remote.files['device_key.json'], wOther);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group(
      'association: "published" is bound to the EXACT intended wrapper '
      '(Stage 5 completion prompt s3 items 5-6). EVIDENCE: NOT EXECUTED', () {
    /// A DIFFERENT wrapper (fresh salts/nonces) that unwraps to the SAME MK.
    Future<String> sameMkDifferentWrap(
        MasterKeyLocalRecord local, String password) async {
      final Uint8List? mk = await PasswordKeyDerivation.unwrapMasterKeyWithRecovery(
        wrapJson: local.recoveryWrap,
        rawPassword: password,
        mnemonicWords: _mnemonic,
      );
      try {
        return await PasswordKeyDerivation.wrapMasterKeyWithRecovery(
          masterKeyBytes: mk!,
          rawPassword: password,
          mnemonicWords: _mnemonic,
        );
      } finally {
        if (mk != null) mk.fillRange(0, mk.length, 0);
      }
    }

    test(
        'N-1: pending rotation, remote holds a THIRD wrapper that unwraps to '
        'the same MK: recorded as conflict, never published, remote untouched',
        () async {
      final FakeGithubRemote remote = FakeGithubRemote();
      final MasterKeyLocalRecord local = await pendingRotation(remote);
      final String third = await sameMkDifferentWrap(local, _p2);
      expect(third, isNot(local.recoveryWrap));
      expect(third, isNot(local.previousPublishedRecoveryWrap));
      remote.files['device_key.json'] = third;
      remote.branchSha = 'c' * 40;
      final int mutationsBefore = remote.mutationCount;
      final token = await unlockToken(_p2);
      await expectLater(
        MasterKeyProductionService.instance.associateRemote(
          service: remote.service,
          password: _p2,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
          authorizationToken: token,
        ),
        throwsStateError,
      );
      final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
      expect(after.remoteRecoveryStatus, RemoteRecoveryStatus.conflict);
      expect(after.recoveryWrap, local.recoveryWrap);
      expect(after.previousPublishedRecoveryWrap,
          local.previousPublishedRecoveryWrap);
      expect(remote.files['device_key.json'], third);
      expect(remote.mutationCount, mutationsBefore);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(
        'N-2: unpublished local, remote holds a DIFFERENT wrapper for the SAME '
        'MK: recorded as conflict, never published, remote untouched',
        () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _p1,
        mnemonicWords: _mnemonic,
      );
      final MasterKeyLocalRecord local = (await MasterKeyLocalStore.read())!;
      final String other = await sameMkDifferentWrap(local, _p1);
      expect(other, isNot(local.recoveryWrap));
      final FakeGithubRemote remote = FakeGithubRemote()
        ..seed('device_key.json', other);
      final int mutationsBefore = remote.mutationCount;
      final token = await unlockToken(_p1);
      await expectLater(
        MasterKeyProductionService.instance.associateRemote(
          service: remote.service,
          password: _p1,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
          authorizationToken: token,
        ),
        throwsStateError,
      );
      final MasterKeyLocalRecord after = (await MasterKeyLocalStore.read())!;
      expect(after.remoteRecoveryStatus, RemoteRecoveryStatus.conflict);
      expect(after.recoveryWrap, local.recoveryWrap);
      expect(remote.files['device_key.json'], other);
      expect(remote.mutationCount, mutationsBefore);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(
        'N-3 (SOURCE-REVIEWED ONLY): every "published" marker in the '
        'association decision tree is preceded by shared-state initialization '
        'and a final paired read', () {
      final String prod = File(
              '${Directory.current.path}/lib/core/master_key_production_service.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final int start =
          prod.indexOf('Future<void> _associateWithObservedRemote(');
      final int end = prod.indexOf(
          '/// Authenticated-session operation (see [associateRemote]', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final String body = prod.substring(start, end);
      final RegExp published =
          RegExp(r'remoteRecoveryStatus:\s*RemoteRecoveryStatus\.published');
      final List<RegExpMatch> hits = published.allMatches(body).toList();
      expect(hits.length, 2,
          reason: 'exact-wrapper route + rotation-publication route only');
      for (final RegExpMatch m in hits) {
        final int init =
            body.lastIndexOf('_initializeOrJoinState(', m.start);
        expect(init, greaterThan(-1),
            reason: 'state initialization precedes the marker');
        final int read = body.indexOf('fetchNoteFilesWithRefSha(', init);
        expect(read, greaterThan(init));
        expect(read, lessThan(m.start),
            reason: 'a final paired read sits between init and the marker');
      }
    });
  });

  group(
      'static: one decision tree and snapshot plumbing (SOURCE-REVIEWED '
      'ONLY)', () {
    String code(String rel) => File('${Directory.current.path}/lib/$rel')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test(
        'association has a single decision tree carrying the snapshot; '
        'rotation takes the expected prior wrapper', () {
      final String prod = code('core/master_key_production_service.dart');
      expect('_associateWithObservedRemote('.allMatches(prod).length, 3,
          reason: 'definition + the two routes');
      expect(prod, contains('pairedSnapshot: observed'));
      expect(prod, contains('PasswordStateManager._validateObservedState'));
      expect(prod, contains('expectedPriorDeviceKeyJson: remoteWrap'));
      expect('revalidateAfterKdf()'.allMatches(prod).length, 3,
          reason: 'definition + two post-KDF call sites');
      final String psm = code('core/password_state_manager.dart');
      expect(psm, contains('fetchNoteFilesWithRefSha('));
      expect(
          psm,
          contains(
              'jsonEncode(currentDeviceKey) != expectedPriorDeviceKeyJson'));
      expect(psm, contains('expectedParentSha: observed.refSha'));
    });
  });
}
