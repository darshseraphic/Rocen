import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/github_backup_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/fake_github_remote.dart';

/// Effective-branch policy, coherent two-file snapshots and the strict
/// pinned-SHA fake. Needs the test-control define (setUp uses the destructive
/// resets): flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true
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
const String _password = 'BlockB!Password44';

Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_branch_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    ssm.finishBootstrap();
  });

  tearDown(() => ssm.lockSync());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

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

  void expectOnlyBranch(FakeGithubRemote r, String branch) {
    expect(r.refReads, isNotEmpty);
    expect(r.refReads.toSet(), <String>{branch},
        reason: 'branch-reference reads: ${r.refReads}');
    expect(r.mutationBranches.toSet().difference(<String>{branch}), isEmpty,
        reason: 'protected writes: ${r.mutationBranches}');
    for (final String? b in r.contentsReadBranches.whereType<String>()) {
      expect(b, branch, reason: 'a Contents read was answered from $b');
    }
    for (final String req in r.contentsRequests) {
      if (!req.startsWith('GET ')) continue;
      final String ref = req.split('ref=').last;
      expect(ref == branch || r.branchOfSha(ref) == branch, isTrue,
          reason: 'Contents request "$req" is not pinned to $branch');
    }
    for (final String? b in r.commitParentBranches) {
      expect(b, branch, reason: 'a commit was built on a $b parent');
    }
  }

  group('effective branch is resolved once and used everywhere', () {
    test(
        'B1: default branch is "master" and a separate "main" branch holds '
        'DIFFERENT device_key.json: the Settings sequence (validate, '
        'pre-check read, establish) reads master only, never adopts main\'s '
        'authority, and writes nothing', () async {
      final remote = FakeGithubRemote(defaultBranch: 'master')
        ..seed('README.md', 'readme');
      remote.addBranch('main', <String, String>{
        'device_key.json': '{"from":"main-branch"}',
      });
      final GithubBackupService service = remote.implicitService;

      await service.validateRepositoryAccess(); // Settings validates first
      // Settings' UX pre-check read of the authority file:
      expect(await service.fetchNoteFile('device_key.json'), isNull,
          reason: "must NOT return main's wrapper");

      // master is already initialised without an authority record: the
      // existing development-repository rule refuses first-device setup.
      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: service,
          repository: 'owner/repo',
        ),
        throwsA(predicate((Object e) =>
            e is StateError && e.message.contains('already initialized'))),
      );
      expectOnlyBranch(remote, 'master');
      expect(remote.mutationCount, 0);
      expect(
          Hive.box(MasterKeyLocalStore.boxName)
              .get(MasterKeyLocalStore.recordKey),
          isNull,
          reason: "no local authority from main's device_key.json");
      expect(remote.branchFiles('main'),
          <String, String>{'device_key.json': '{"from":"main-branch"}'});
    });

    test(
        'B2: authority that exists on the default branch "master" is the '
        'one recovered, never the one on "main"', () async {
      final String wMaster = await wrapFromFreshDevice();
      final String wMain = await wrapFromFreshDevice();
      final remote = FakeGithubRemote(defaultBranch: 'master')
        ..seed('device_key.json', wMaster);
      remote.addBranch('main', <String, String>{'device_key.json': wMain});

      await remote.implicitService.validateRepositoryAccess();
      await MasterKeyProductionService.instance.recoverFromRemote(
        service: remote.implicitService,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
      );
      expect((await MasterKeyLocalStore.read())!.recoveryWrap, wMaster);
      expectOnlyBranch(remote, 'master');
    });

    test(
        'B3: an EMPTY repository still supports first-run initialization '
        '(implicit branch)', () async {
      final remote = FakeGithubRemote(defaultBranch: 'trunk');
      await remote.implicitService.validateRepositoryAccess();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.implicitService,
        repository: 'owner/repo',
      );
      expect(remote.files.containsKey('device_key.json'), isTrue);
      expect(remote.files.containsKey('password_state.json'), isTrue);
      expectOnlyBranch(remote, 'trunk');
    });

    test(
        'B4: an explicit NON-default branch in an EMPTY repository fails '
        'closed (the Contents API contract cannot establish creating a '
        'named non-default branch there); nothing is written', () async {
      final remote = FakeGithubRemote();
      final GithubBackupService service = remote.serviceFor(branch: 'feature');
      await service.validateRepositoryAccess();
      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: service,
          repository: 'owner/repo',
        ),
        throwsA(isA<GithubBranchMissingException>()),
      );
      expect(remote.mutationCount, 0);
      expect(
          Hive.box(MasterKeyLocalStore.boxName)
              .get(MasterKeyLocalStore.recordKey),
          isNull);
    });

    test(
        'B5: an EXPLICIT non-main branch that is missing is never replaced '
        'by the default branch: validation passes, every authority read/'
        'setup refuses, nothing is created or published', () async {
      final String w = await wrapFromFreshDevice();
      final remote = FakeGithubRemote()..seed('device_key.json', w);
      final before = Map<String, String>.from(remote.files);
      final GithubBackupService service = remote.serviceFor(branch: 'feature');

      await service.validateRepositoryAccess(); // production validates first
      await expectLater(service.fetchNoteFileWithRefSha('device_key.json'),
          throwsA(isA<GithubBranchMissingException>()));
      await expectLater(
        MasterKeyProductionService.instance.recoverFromRemote(
          service: service,
          password: _password,
          mnemonicWords: _mnemonic,
          repository: 'owner/repo',
        ),
        throwsA(isA<GithubBranchMissingException>()),
      );
      expect(
          Hive.box(MasterKeyLocalStore.boxName)
              .get(MasterKeyLocalStore.recordKey),
          isNull);
      expect(remote.mutationCount, 0);
      expect(remote.files, before);
      expect(remote.contentsRequests, isEmpty);
    });

    test(
        'B6: first-device setup on a missing explicit branch while the '
        'default branch has device_key.json but NO password_state.json: no '
        'local authority, no publication, no promotion', () async {
      final remote = FakeGithubRemote()
        ..seed('device_key.json', '{"authority":"on-default-branch"}');
      final before = Map<String, String>.from(remote.files);
      final GithubBackupService service = remote.serviceFor(branch: 'feature');

      await service.validateRepositoryAccess();
      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: service,
          repository: 'owner/repo',
        ),
        throwsA(isA<GithubBranchMissingException>()),
      );
      expect(
          Hive.box(MasterKeyLocalStore.boxName)
              .get(MasterKeyLocalStore.recordKey),
          isNull,
          reason: 'no conflicting local authority was created');
      expect(remote.mutationCount, 0);
      expect(remote.files, before);
      expect(remote.contentsRequests, isEmpty,
          reason: 'neither authority file was read from the default branch');
    });

    test(
        'B7: both authority files of an existing branch are read from ONE '
        'pinned snapshot (same commit sha, no unpinned read)', () async {
      final remote = FakeGithubRemote()
        ..seed('device_key.json', '{"d":1}')
        ..seed('password_state.json', '{"p":1}');
      final snap = await remote.service.fetchNoteFilesWithRefSha(
          <String>['device_key.json', 'password_state.json']);
      expect(snap.refSha, isNotNull);
      expect(snap.contents['device_key.json'], isNotNull);
      expect(snap.contents['password_state.json'], isNotNull);
      final reads = remote.contentsRequests;
      expect(reads, hasLength(2));
      for (final String r in reads) {
        expect(r.endsWith('ref=${snap.refSha}'), isTrue, reason: r);
      }
    });

    test(
        'B9: plain fetchNoteFile distinguishes a missing FILE on an existing '
        'branch (null), a missing EXPLICIT branch (throws) and an empty '
        'repository (null)', () async {
      // file missing on an existing branch
      final r1 = FakeGithubRemote()..seed('other.json', '{}');
      expect(await r1.service.fetchNoteFile('device_key.json'), isNull);
      expect(await r1.implicitService.fetchNoteFile('device_key.json'), isNull);

      // explicit branch missing in a non-empty repository, after validation
      final r2 = FakeGithubRemote()..seed('device_key.json', '{"d":1}');
      final GithubBackupService s2 = r2.serviceFor(branch: 'feature');
      await s2.validateRepositoryAccess();
      await expectLater(s2.fetchNoteFile('device_key.json'),
          throwsA(isA<GithubBranchMissingException>()),
          reason: 'not a misleading "file absent", and never default data');
      await expectLater(s2.fetchNoteFileWithRefSha('device_key.json'),
          throwsA(isA<GithubBranchMissingException>()));
      expect(r2.contentsReadBranches.every((b) => b != 'main'), isTrue,
          reason: 'no read was answered from the default branch');

      // genuinely empty repository: plain absence
      final r3 = FakeGithubRemote();
      expect(await r3.service.fetchNoteFile('device_key.json'), isNull);
      expect(await r3.implicitService.fetchNoteFile('device_key.json'), isNull);
    });

    test(
        'B10: cached implicit branch removed after default changes fails '
        'closed through validate, Settings pre-check, then setup', () async {
      final remote = FakeGithubRemote()..seed('history.json', '{}');
      final GithubBackupService service = remote.implicitService;
      await service.validateRepositoryAccess(); // caches main
      remote.addBranch('master', <String, String>{
        'device_key.json': '{"authority":"master-only"}',
        'password_state.json': '{}',
      });
      remote.defaultBranch = 'master'; // metadata now points elsewhere
      remote.removeBranch('main'); // stale cached ref is unavailable

      await expectLater(service.fetchNoteFile('device_key.json'),
          throwsA(isA<GithubBranchMissingException>()));
      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: service,
          repository: 'owner/repo',
        ),
        throwsA(isA<GithubBranchMissingException>()),
      );
      expect(remote.mutationCount, 0);
      expect(
          Hive.box(MasterKeyLocalStore.boxName)
              .get(MasterKeyLocalStore.recordKey),
          isNull);
      expect(remote.branchFiles('master')!['device_key.json'],
          '{"authority":"master-only"}',
          reason: 'stale service never adopts another branch authority');
      expectOnlyBranch(remote, 'main');
    });

    test(
        'B11: explicit branch equal to the default but removed after '
        'validation is missing, even though cached metadata still names it',
        () async {
      final remote = FakeGithubRemote()..seed('history.json', '{}');
      final GithubBackupService service = remote.service;
      await service.validateRepositoryAccess();
      remote.addBranch('master', <String, String>{'history.json': '{}'});
      remote.removeBranch('main');
      await expectLater(service.fetchNoteFile('device_key.json'),
          throwsA(isA<GithubBranchMissingException>()));
      expect(remote.mutationCount, 0);
    });

    test(
        'B12: missing explicit branch in non-empty repository refuses a '
        'plain read and setup; existing branch missing file remains null',
        () async {
      final remote = FakeGithubRemote()..seed('history.json', '{}');
      final GithubBackupService service = remote.serviceFor(branch: 'feature');
      await service.validateRepositoryAccess();
      await expectLater(service.fetchNoteFile('absent.json'),
          throwsA(isA<GithubBranchMissingException>()));
      await expectLater(
        MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
          remoteService: service,
          repository: 'owner/repo',
        ),
        throwsA(isA<GithubBranchMissingException>()),
      );
      expect(remote.mutationCount, 0);
      expect(
          Hive.box(MasterKeyLocalStore.boxName)
              .get(MasterKeyLocalStore.recordKey),
          isNull);
      expect(await remote.service.fetchNoteFile('absent.json'), isNull,
          reason: 'missing file on an existing branch is ordinary absence');
    });

    test('B8: invalid explicit branch names are refused before any request',
        () async {
      for (final String bad in <String>[
        'a b',
        'a?b',
        'a#b',
        'a%2Fb',
        '../x',
        'a..b',
        'x.lock',
        '/x',
        'x/',
        'a//b',
        '',
      ]) {
        final remote = FakeGithubRemote();
        await expectLater(
          remote.serviceFor(branch: bad).fetchNoteFile('notes/a.json'),
          throwsA(isA<GithubSyncException>()),
          reason: 'branch "$bad"',
        );
        expect(remote.requestCount, 0, reason: 'branch "$bad"');
      }
    });
  });

  group(
      'the fake resolves pinned refs STRICTLY (unknown sha never returns '
      'current content)', () {
    test(
        'P1: a nonexistent SHA is not found while the current file holds '
        'different content; valid current/historical/branch refs work',
        () async {
      final remote = FakeGithubRemote()..seed('device_key.json', '{"v":"old"}');
      final String oldSha = remote.branchSha!;
      remote.files['device_key.json'] = '{"v":"new"}';
      remote.branchSha = 'a' * 40; // current head commit

      final GithubBackupService s = remote.service;
      expect(await s.fetchNoteFile('device_key.json', ref: 'f' * 40), isNull,
          reason: 'unknown sha must NOT be answered with current content');
      expect(await s.fetchNoteFile('device_key.json', ref: 'abcd1234'), isNull);
      expect(await s.fetchNoteFile('device_key.json', ref: 'a' * 40),
          <String, dynamic>{'v': 'new'}, // exact current commit
          reason: 'valid current head');
      expect(await s.fetchNoteFile('device_key.json', ref: oldSha),
          <String, dynamic>{'v': 'old'}, // recorded historical snapshot
          reason: 'valid historical snapshot');
      expect(await s.fetchNoteFile('device_key.json', ref: 'main'),
          <String, dynamic>{'v': 'new'}, // branch name
          reason: 'branch name');
    });
  });

  group('static: effective-branch policy (SOURCE-REVIEWED ONLY)', () {
    String code(String rel) => File('${Directory.current.path}/lib/$rel')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test(
        'no second branch source: no _resolvedBranch, no constructor '
        'default of "main", reads and writes use _effectiveBranchName', () {
      final String svc = code('core/github_backup_service.dart');
      expect(svc, isNot(contains('_resolvedBranch')));
      expect(svc, isNot(contains("this.branch = 'main'")));
      expect(svc, contains('Future<String> _effectiveBranchName()'));
      expect('await _effectiveBranchName()'.allMatches(svc).length,
          greaterThanOrEqualTo(5));
      expect(svc, isNot(contains(r'refs/heads/$branch')));
    });

    test('first-device setup reads both authority files from one snapshot', () {
      final String prod = code('core/master_key_production_service.dart');
      expect(prod, contains('fetchNoteFilesWithRefSha('));
      expect(prod, isNot(contains("fetchNoteFile('password_state.json')")));
    });
  });
}
