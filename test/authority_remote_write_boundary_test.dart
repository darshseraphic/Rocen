import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'support/fake_github_remote.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/github_backup_service.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/activation_contract.dart';

/// Boundary tests for security-authority remote/local mutations
/// (PasswordStateManager + GithubBackupService) and for the
/// SecurityCheckpoints test-control boundary.
///
/// Tests that PAUSE production code need the test-control build flag:
///
///   flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true
///
/// This file's setUp uses the destructive resets, so the whole file needs
/// the define. Normal-build (define OFF) checkpoint behaviour is verified
/// by the separate `normal_build_checkpoint_isolation_test.dart`.
///
/// Evidence: written against the real production path; NOT executed in the
/// authoring environment (no Dart/Flutter runtime).
const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];
const String _password = 'BlockB!Password44';

final Object _skipUnlessControl = SecurityCheckpoints.isTestControlEnabled
    ? false
    : 'run with --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true';



String encodeDeep(String plain, int layers) {
  String v = plain;
  for (int i = 0; i < layers; i++) {
    v = v.replaceAll('%', '%25');
  }
  return v;
}

String _src(String rel) =>
    File('${Directory.current.path}/lib/$rel').readAsStringSync();

Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_authority_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    SecurityCheckpoints.reset();
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
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

  Future<SessionAuthorizationToken> unlockedToken() async {
    ssm.finishBootstrap();
    await ssm.unlock(
      password: _password,
      activateRoot: satisfyActivationContract,
      teardownRoot: () {},
    );
    return ssm.captureAuthorization();
  }

  group('reserved authority paths (pure canonicalisation)', () {
    test('every harmless variation of an authority path is reserved', () {
      const List<String> variants = <String>[
        'device_key.json',
        'password_state.json',
        '/device_key.json',
        './device_key.json',
        'sub/../device_key.json',
        'DEVICE_KEY.JSON',
        'device_key.json.',
        'device_key.json ',
        'device_key%2Ejson',
        '%64evice_key.json',
        'device_key%252Ejson',
        r'a\..\device_key.json',
        '//password_state.json',
        'x/./../password_state.json',
        'Password_State.JSON',
        // Deep encodings (the decoder must reach a fixed point or fail closed).
        '%2525252564evice_key.json', // 5 layers
        '%252525252564evice_key.json', // 6 layers
        '%25252525252564evice_key.json', // 7 layers
        '%2525252525252564evice_key.json', // 8 layers
        // Encoded separators / traversal combined with reserved names.
        '%2e%2e%2fdevice_key.json',
        'a%2F..%2Fdevice_key.json',
        'a%255C..%255Cpassword_state.json',
        'notes%252F..%252Fdevice_key.json',
        '%2Fdevice_key.json',
        '%2e/%2e%2e/password_state.json',
      ];
      for (final String v in variants) {
        expect(GithubReservedPaths.isReserved(v), isTrue, reason: v);
      }
    });

    String encodeLayers(String plain, int layers) {
      String v = plain;
      for (int i = 0; i < layers; i++) {
        v = v.replaceAll('%', '%25');
      }
      return v;
    }

    test('every encoding depth is reserved: up to maxDecodeLayers it '
        'canonicalises to the authority file, beyond it the result is null '
        '(fail closed) - never an ordinary path', () {
      const String base = '%64evice_key.json'; // one layer over the name
      for (int layers = 0; layers <= 30; layers++) {
        final String encoded = encodeLayers(base, layers);
        expect(GithubReservedPaths.isReserved(encoded), isTrue,
            reason: '$layers extra layers: $encoded');
        final String? n = GithubReservedPaths.normalize(encoded);
        if (layers + 1 <= GithubReservedPaths.maxDecodeLayers) {
          expect(n, 'device_key.json', reason: '$layers');
        } else {
          expect(n, isNull, reason: '$layers: not fully decodable -> null');
        }
      }
    });

    test('deeply encoded ORDINARY paths are also refused by the generic '
        'API (conservative: undecidable == unsafe) but legitimate ordinary '
        'paths are not', () {
      expect(GithubReservedPaths.normalize(encodeLayers('%6eotes/a.json', 20)),
          isNull);
      expect(GithubReservedPaths.isReserved('notes%2Fa.json'), isFalse);
      expect(GithubReservedPaths.normalize('notes%2Fa.json'), 'notes/a.json');
    });

    test('malformed or root-escaping paths fail closed (treated as reserved)',
        () {
      for (final String v in <String>[
        '..',
        '../x',
        'a/../../device_key.json',
        'bad%zz',
        'a\u0000b',
        '',
        '...',
        '%',
        '%2',
        '%zz',
        'device_key%',
        'device_key.json%2',
        '%252',
        '%25252',
        '%c0%af',
        '%00device_key.json',
      ]) {
        expect(GithubReservedPaths.isReserved(v), isTrue, reason: v);
      }
    });

    test('ordinary backup paths are not reserved', () {
      for (final String v in <String>[
        'notes/a.json',
        'device_key.json.bak',
        'notes/device_key.json',
        'backup/2026/notes.enc',
      ]) {
        expect(GithubReservedPaths.isReserved(v), isFalse, reason: v);
      }
    });
  });

  group('generic public backup writes cannot touch authority files', () {
    final List<String> unsafe = <String>[
      'device_key.json',
      './PASSWORD_STATE.json',
      'x/../device_key.json',
      '%2525252564evice_key.json',
      '%2e%2e%2fdevice_key.json',
      'a%2F..%2Fpassword_state.json',
      encodeDeep('%64evice_key.json', 12),
      'bad%zz',
      '../outside.json',
    ];

    test('createFileIfAbsent refuses every unsafe path before any request',
        () async {
      final remote = FakeGithubRemote();
      for (final String path in unsafe) {
        await expectLater(
          remote.service
              .createFileIfAbsent(path: path, content: '{}', message: 'm'),
          throwsA(isA<GithubReservedPathException>()),
          reason: path,
        );
      }
      expect(remote.mutationCount, 0);
      expect(remote.requestCount, 0,
          reason: 'refused before ANY HTTP request was sent');
    });

    test('updateFileWithFastForwardCheck refuses every unsafe path before '
        'any request', () async {
      final remote = FakeGithubRemote();
      for (final String path in unsafe) {
        await expectLater(
          remote.service.updateFileWithFastForwardCheck(
            path: path,
            content: '{}',
            message: 'm',
            expectedParentSha: null,
          ),
          throwsA(isA<GithubReservedPathException>()),
          reason: path,
        );
      }
      expect(remote.mutationCount, 0);
      expect(remote.requestCount, 0);
    });

    test('updateFilesWithFastForwardCheck refuses if ANY key is unsafe, '
        'before any request', () async {
      final remote = FakeGithubRemote();
      for (final String path in unsafe) {
        await expectLater(
          remote.service.updateFilesWithFastForwardCheck(
            updates: <String, String>{'notes/ok.json': '{}', path: '{}'},
            message: 'm',
            expectedParentSha: null,
          ),
          throwsA(isA<GithubReservedPathException>()),
          reason: path,
        );
      }
      expect(remote.mutationCount, 0);
      expect(remote.requestCount, 0);
    });
  });

  group('URI aliases: the validated path IS the request resource', () {
    final List<String> unsafe = <String>[
      'device_key.json#anything',
      'device_key.json?x=1',
      'password_state.json#anything',
      'password_state.json?x=1',
      'device_key.json%23anything', // encoded '#'
      'device_key.json%3Fx=1', // encoded '?'
      'device_key.json%2523anything', // nested-encoded '#'
      'device_key.json%253Fx=1', // nested-encoded '?'
      'password_state.json%252523x', // triple
      'notes/a.json#frag',
      'notes/a.json?x=1',
      'notes/a%23b.json',
      '%2525252564evice_key.json',
      '%2e%2e%2fdevice_key.json',
      'a%2F..%2Fpassword_state.json',
      'notes%252F..%252Fdevice_key.json',
      'bad%zz',
      'device_key.json%',
      encodeDeep('%64evice_key.json', 12),
      '/device_key.json',
      'device_key.json/',
      'a//b.json',
      'a/./b.json',
      'notes/../device_key.json',
      r'a\b.json',
      'trailingdot.json.',
      'trailingspace.json ',
      '',
    ];

    test('createFileIfAbsent: every alias rejected with ZERO requests',
        () async {
      final remote = FakeGithubRemote();
      for (final String path in unsafe) {
        await expectLater(
          remote.service
              .createFileIfAbsent(path: path, content: '{}', message: 'm'),
          throwsA(isA<GithubReservedPathException>()),
          reason: 'create: "$path"',
        );
      }
      expect(remote.requestCount, 0);
      expect(remote.mutationCount, 0);
    });

    test('updateFileWithFastForwardCheck: every alias rejected with ZERO '
        'requests', () async {
      final remote = FakeGithubRemote();
      for (final String path in unsafe) {
        await expectLater(
          remote.service.updateFileWithFastForwardCheck(
            path: path,
            content: '{}',
            message: 'm',
            expectedParentSha: null,
          ),
          throwsA(isA<GithubReservedPathException>()),
          reason: 'update: "$path"',
        );
      }
      expect(remote.requestCount, 0);
    });

    test('updateFilesWithFastForwardCheck: a single alias among ordinary '
        'paths rejects the WHOLE batch with ZERO requests', () async {
      final remote = FakeGithubRemote();
      for (final String path in unsafe) {
        await expectLater(
          remote.service.updateFilesWithFastForwardCheck(
            updates: <String, String>{'notes/ok.json': '{}', path: '{}'},
            message: 'm',
            expectedParentSha: null,
          ),
          throwsA(isA<GithubReservedPathException>()),
          reason: 'multi: "$path"',
        );
      }
      expect(remote.requestCount, 0);
    });

    test('ordinary nested paths still work and the request resource equals '
        'the validated path (single, correct encoding)', () async {
      final remote = FakeGithubRemote();
      await remote.service.createFileIfAbsent(
        path: 'backup/2026/notes.enc',
        content: '{"n":1}',
        message: 'm',
      );
      await remote.service.createFileIfAbsent(
        path: 'my notes/file one.json',
        content: '{"n":2}',
        message: 'm',
      );
      expect(remote.files['backup/2026/notes.enc'], '{"n":1}');
      expect(remote.files['my notes/file one.json'], '{"n":2}');
      expect(remote.contentsRequests.first,
          startsWith('PUT backup/2026/notes.enc '));
      expect(remote.rawContentsPaths.first,
          '/repos/owner/repo/contents/backup/2026/notes.enc',
          reason: 'nested separators stay separators; no encoded "/"');
      expect(remote.contentsSegmentCounts.first, 7,
          reason: 'repos/owner/repo/contents + 3 file segments');
      expect(remote.rawContentsPaths.last,
          '/repos/owner/repo/contents/my%20notes/file%20one.json',
          reason: 'each segment encoded once, not double-encoded');

      // single-file update and multi-file update with ordinary paths
      await remote.service.updateFileWithFastForwardCheck(
        path: 'backup/b.json',
        content: '{"b":1}',
        message: 'm',
        expectedParentSha: remote.branchSha,
      );
      expect(remote.files['backup/b.json'], '{"b":1}');
      await remote.service.updateFilesWithFastForwardCheck(
        updates: <String, String>{
          'backup/c.json': '{"c":1}',
          'backup/d/e.json': '{"d":1}',
        },
        message: 'm',
        expectedParentSha: remote.branchSha,
      );
      expect(remote.files['backup/c.json'], '{"c":1}');
      expect(remote.files['backup/d/e.json'], '{"d":1}');
      expect(remote.files.containsKey('device_key.json'), isFalse);
    });

    test('the authority writers build the same safe resource: create of '
        'device_key.json targets exactly /contents/device_key.json',
        () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      await Hive.box(MasterKeyLocalStore.boxName).clear();
      final remote = FakeGithubRemote();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      final puts =
          remote.contentsRequests.where((r) => r.startsWith('PUT ')).toList();
      expect(puts.single, startsWith('PUT device_key.json '));
      expect(remote.rawContentsPaths.where((p) => p.contains('device_key')).first,
          '/repos/owner/repo/contents/device_key.json');
    });
  });

  group('repository identifier validation: one safe URI path for every '
      'endpoint', () {
    final List<String> bad = <String>[
      'owner/repo?x=1',
      'owner/repo#frag',
      'owner/re%70o',
      'owner%2Frepo',
      'owner%2fRepo',
      'own%252Fer/repo',
      'owner/repo%2F..%2Fother',
      'owner/repo/extra',
      '/repo',
      'owner/',
      'owner',
      '',
      'owner /repo',
      'owner/re po',
      ' owner/repo',
      'owner/repo ',
      'owner/repo\n',
      'owner\t/repo',
      'owner/repo\u00a0',
      'ow ner/repo',
      r'owner\repo',
      'owner/..',
      'owner/.',
      '-owner/repo',
      'owner-/repo',
      'owner//repo',
      'o' * 40 + '/repo',
    ];

    GithubBackupService svcFor(FakeGithubRemote r, String repoPath) =>
        GithubBackupService(
          token: 'test-token',
          repoPath: repoPath,
          client: r.client,
        );

    test('malformed identifiers are rejected by EVERY request-issuing method '
        'with ZERO HTTP requests', () async {
      for (final String repo in bad) {
        final remote = FakeGithubRemote();
        final GithubBackupService s = svcFor(remote, repo);
        final List<Future<Object?> Function()> calls =
            <Future<Object?> Function()>[
          () => s.validateRepositoryAccess(),
          () => s.fetchNoteFile('notes/a.json'),
          () => s.fetchNoteFileWithRefSha('notes/a.json'),
          () => s.createFileIfAbsent(
              path: 'notes/a.json', content: '{}', message: 'm'),
          () => s.updateFileWithFastForwardCheck(
              path: 'notes/a.json',
              content: '{}',
              message: 'm',
              expectedParentSha: null),
          () => s.updateFilesWithFastForwardCheck(
              updates: <String, String>{'notes/a.json': '{}'},
              message: 'm',
              expectedParentSha: null),
        ];
        for (final Future<Object?> Function() call in calls) {
          await expectLater(call(), throwsA(isA<GithubSyncException>()),
              reason: 'repo "$repo"');
        }
        expect(remote.requestCount, 0, reason: 'repo "$repo"');
      }
    });

    test('an ordinary owner/repository works across metadata, ref, tree, '
        'commit and Contents calls, and every request names exactly that '
        'repository', () async {
      final remote = FakeGithubRemote(repoPath: 'Owner-1/my.repo_x');
      remote.seed('notes/a.json', '{"a":1}');
      final GithubBackupService s = remote.service;
      await s.validateRepositoryAccess(); // metadata
      expect(await s.fetchNoteFile('notes/a.json'), isNotNull); // contents
      final snap = await s.fetchNoteFileWithRefSha('notes/a.json'); // ref
      expect(snap.refSha, isNotNull);
      await s.updateFileWithFastForwardCheck(
        // tree + commit + ref update
        path: 'notes/b.json',
        content: '{"b":1}',
        message: 'm',
        expectedParentSha: remote.branchSha,
      );
      expect(remote.files['notes/b.json'], '{"b":1}');
      expect(remote.mutationLog.any((m) => m.contains('/git/trees')), isTrue);
      expect(remote.mutationLog.any((m) => m.contains('/git/commits')), isTrue);
      expect(remote.mutationLog.any((m) => m.contains('/git/refs/heads/')), isTrue);
      expect(remote.unroutedRequests, isEmpty,
          reason: 'every request addressed /repos/Owner-1/my.repo_x');
    });

    test('no raw interpolation or string parsing builds a URL (static)', () {
      final String svc = _src('core/github_backup_service.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(svc, isNot(contains('Uri.parse(')));
      expect(svc, isNot(contains('Uri _api(')));
      expect(svc, isNot(contains('_api(')));
      expect(svc, isNot(contains(r'repos/$repoPath')),
          reason: 'repoPath appears only in messages, never in a URL string');
      expect(svc, contains('_validatedRepoComponents()'));
    });
  });

  group('authority scope is EXACT and LITERAL (pure scope function used by '
      'the grant)', () {
    const Set<String> deviceOnly = <String>{'device_key.json'};
    const Set<String> stateOnly = <String>{'password_state.json'};
    const Set<String> both = <String>{'device_key.json', 'password_state.json'};

    final List<String> notExact = <String>[
      'Device_Key.json', // case variants
      'DEVICE_KEY.JSON',
      'device_key.JSON',
      'device_key.json.', // trailing dot
      'device_key.json ', // trailing space
      'device_key.json  ',
      'device_key%2Ejson', // percent escapes
      '%64evice_key.json',
      'device_key.json%2523x',
      'device_key.json%00',
      'device_key.json?x=1', // query / fragment
      'device_key.json#frag',
      r'device_key.json\x', // backslash
      r'sub\..\device_key.json',
      './device_key.json', // traversal / path forms
      'sub/../device_key.json',
      '../device_key.json',
      '/device_key.json',
      'device_key.json/',
      'a/b/device_key.json',
      'device_key.json\u0000',
      'notes/a.json',
      '',
    ];

    test('createFile / updateFile shape: only the exact permitted filename '
        'passes; every variant is rejected', () {
      for (final String p in notExact) {
        expect(() => GithubReservedPaths.requireExactAuthorityTargets(
              <String>[p], deviceOnly),
            throwsA(isA<GithubReservedPathException>()),
            reason: 'single: "$p"');
      }
      expect(() => GithubReservedPaths.requireExactAuthorityTargets(
              <String>['device_key.json'], deviceOnly),
          returnsNormally);
      expect(() => GithubReservedPaths.requireExactAuthorityTargets(
              <String>['password_state.json'], stateOnly),
          returnsNormally);
      // an exact name that is NOT in this grant's set is also refused
      expect(() => GithubReservedPaths.requireExactAuthorityTargets(
              <String>['password_state.json'], deviceOnly),
          throwsA(isA<GithubReservedPathException>()));
    });

    test('updateFiles shape: ONE bad entry rejects the whole batch; exact '
        'names in any order pass', () {
      for (final String p in notExact) {
        for (final String exact in both) {
          expect(() => GithubReservedPaths.requireExactAuthorityTargets(
                <String>[exact, p], both),
              throwsA(isA<GithubReservedPathException>()),
              reason: 'multi: "$exact" + "$p"');
          expect(() => GithubReservedPaths.requireExactAuthorityTargets(
                <String>[p, exact], both),
              throwsA(isA<GithubReservedPathException>()),
              reason: 'multi: "$p" + "$exact"');
        }
      }
      expect(() => GithubReservedPaths.requireExactAuthorityTargets(
              <String>['password_state.json', 'device_key.json'], both),
          returnsNormally);
    });

    test('the grant uses exactly this function and keeps no normalisation '
        '(SOURCE-REVIEWED ONLY: a grant cannot be minted by a test)', () {
      final String prod = _src('core/master_key_production_service.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final int g = prod.indexOf('final class GithubAuthorityWriteGrant {');
      final String grant =
          prod.substring(g, prod.indexOf('GithubAuthorityWriteGrant _newGrant('));
      expect(grant, contains('GithubReservedPaths.requireExactAuthorityTargets(paths, _paths)'));
      expect(grant, isNot(contains('normalize(')));
      expect(grant, contains('GithubReservedPaths.literalSegments(path)'));

      final String svc = _src('core/github_backup_service.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // All three authority entry points validate every supplied path as a
      // literal path BEFORE grant.beginMutation (budget consumption).
      for (final String kind in <String>['createFile', 'updateFile,', 'updateFiles,']) {
        final int b = svc.indexOf('grant.beginMutation(GithubAuthorityMutation.$kind');
        expect(b, greaterThan(0), reason: kind);
        expect(svc.substring(b - 260, b), contains('GithubReservedPaths.literalSegments(path)'),
            reason: kind);
      }
    });

    test('valid authority writes place the EXACT granted path in the Contents '
        'URL and in the Git-tree payload (production path, transport-level)',
        () async {
      final remote = FakeGithubRemote();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      expect(remote.rawContentsPaths.where((p) => p.contains('device_key')),
          everyElement('/repos/owner/repo/contents/device_key.json'));
      expect(remote.writtenPaths.toSet(),
          <String>{'device_key.json', 'password_state.json'});
      for (final String p in remote.writtenPaths) {
        expect(<String>{'device_key.json', 'password_state.json'}.contains(p),
            isTrue,
            reason: 'byte-identical granted name, got "$p"');
      }
    });
  });

  group('authorized authority mutations still work', () {
    test('bootstrap (pre-session) initialization writes through the '
        'authority path', () async {
      final remote = FakeGithubRemote();
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
        remoteService: remote.service,
        repository: 'owner/repo',
      );
      expect(remote.files.containsKey('device_key.json'), isTrue);
      expect(remote.files.containsKey('password_state.json'), isTrue);
      expect(remote.mutationCount, greaterThanOrEqualTo(2));
      expect(
        remote.writtenPaths.toSet(),
        <String>{'device_key.json', 'password_state.json'},
        reason: 'only the permitted authority paths were written',
      );
      expect(ssm.state, isNot(SessionState.unlocked),
          reason: 'bootstrap needs and creates no session');
      expect(PasswordStateManager.getKnownGeneration(), 1);
    });

    test('associateRemote with a real token registers the device through '
        'the authority path', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      final local = (await MasterKeyLocalStore.read())!;
      final remote = FakeGithubRemote()..seed('device_key.json', local.recoveryWrap);
      final token = await unlockedToken();
      await MasterKeyProductionService.instance.associateRemote(
        service: remote.service,
        password: _password,
        mnemonicWords: _mnemonic,
        repository: 'owner/repo',
        authorizationToken: token,
      );
      expect(remote.files.containsKey('password_state.json'), isTrue);
      expect(PasswordStateManager.getKnownGeneration(), 1);
    });
  });

  group('stale operations never start a protected PasswordStateManager '
      'mutation (deterministic)', () {
    Future<FakeGithubRemote> preparedRemote() async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      final local = (await MasterKeyLocalStore.read())!;
      // A pre-existing device id means the first protected write seam is the
      // remote password-state write itself.
      await Hive.box(MasterKeyLocalStore.boxName)
          .put('device_id', 'device-fixed-for-test');
      return FakeGithubRemote()..seed('device_key.json', local.recoveryWrap);
    }

    test('lock while paused before the remote password_state write: the '
        'write is never initiated and nothing local is recorded', () async {
      final remote = await preparedRemote();
      final token = await unlockedToken();
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
      // Pause immediately before the remote password-state mutation.
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite);
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await expectLater(
          attempt, throwsA(isA<SessionAuthorizationRequiredException>()));
      expect(remote.mutationCount, 0);
      expect(remote.files.containsKey('password_state.json'), isFalse);
      expect(PasswordStateManager.getKnownGeneration(), 0);
    }, skip: _skipUnlessControl);

    test('lock after the remote write landed but before local bookkeeping: '
        'known generation / device number are NOT recorded', () async {
      final remote = await preparedRemote();
      final token = await unlockedToken();
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
          SecurityCheckpoint.beforeProtectedWrite); // remote state write
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.beforeProtectedWrite); // local bookkeeping
      expect(remote.files.containsKey('password_state.json'), isTrue,
          reason: 'the already-started remote write completed');
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await expectLater(
          attempt, throwsA(isA<SessionAuthorizationRequiredException>()));
      expect(PasswordStateManager.getKnownGeneration(), 0,
          reason: 'stale work must not update local bookkeeping');
      expect(PasswordStateManager.getDeviceNumber(), isNull);
    }, skip: _skipUnlessControl);
  });

  group('check-to-mutation boundary (local PSM writes)', () {
    test('a stale operation at the device-id write never starts it: no '
        'device id is persisted', () async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      final local = (await MasterKeyLocalStore.read())!;
      final remote = FakeGithubRemote()
        ..seed('device_key.json', local.recoveryWrap);
      final token = await unlockedToken();
      expect(Hive.box(MasterKeyLocalStore.boxName).get('device_id'), isNull);

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
          SecurityCheckpoint.beforeProtectedWrite); // device-id write
      ssm.lockSync();
      SecurityCheckpoints.release(SecurityCheckpoint.beforeProtectedWrite);
      await expectLater(
          attempt, throwsA(isA<SessionAuthorizationRequiredException>()));
      expect(Hive.box(MasterKeyLocalStore.boxName).get('device_id'), isNull,
          reason: 'the stale device-id write was never started');
      expect(remote.mutationCount, 0);
    }, skip: _skipUnlessControl);

    test('SCOPE OF THE GUARANTEE (documented, SOURCE-REVIEWED ONLY): a '
        'write that has ALREADY started is not cancelled by lockSync(); the '
        'guarantee is that a stale operation never starts one', () {
      final String psm = _src('core/password_state_manager.dart');
      expect(psm, contains('A Hive write or HTTP request that has already started cannot be'));
      expect(psm, contains('cancelled by `lockSync()`'));
    });
  });

  group('SecurityCheckpoints control boundary', () {
    test('with the flag: unarmed reach is still null; armed reach pauses '
        'until released', () async {
      SecurityCheckpoints.arm(SecurityCheckpoint.afterTekDerivation);
      expect(SecurityCheckpoints.reach(SecurityCheckpoint.afterNekDerivation),
          isNull);
      final Future<void>? paused =
          SecurityCheckpoints.reach(SecurityCheckpoint.afterTekDerivation);
      expect(paused, isNotNull);
      bool done = false;
      paused!.then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      SecurityCheckpoints.release(SecurityCheckpoint.afterTekDerivation);
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    }, skip: _skipUnlessControl);
  });

  group('static boundary audit (SOURCE-REVIEWED ONLY)', () {
    String code(String rel) => _src(rel)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('PasswordStateManager exposes no public mutation', () {
      final String psm = code('core/password_state_manager.dart');
      expect(psm, contains("part of 'master_key_production_service.dart'"));
      expect(psm, isNot(contains('static Future<void> initializeOrJoinState(')));
      expect(psm, isNot(contains('static Future<void> publishRotationAtomically(')));
      expect(psm, isNot(contains('static String getOrCreateDeviceId(')));
      expect(psm, contains('static Future<void> _initializeOrJoinState('));
      expect(psm, contains('static Future<void> _publishRotationAtomically('));
      expect(psm, isNot(contains('box.put(')),
          reason: 'every local write is a fenced putAll');
      // Every putAll is preceded by the fenced seam.
      expect('await box.putAll('.allMatches(psm).length, 2);
      // 3. No async fence helper: it would reopen a check-to-mutation gap.
      expect(psm, isNot(contains('_fenceBeforeWrite')));
      // Every protected mutation: final fence.check() with NO await between
      // it and the mutation start.
      final RegExp boundary = RegExp(
          r'fence\.check\(\); // final check; the mutation starts in this same turn\n([^;]*?)(await box\.putAll\(|await service\.authority\w+\()');
      final Iterable<RegExpMatch> ms = boundary.allMatches(psm);
      expect(ms.length, 5, reason: '2 local writes + 3 remote writes');
      for (final RegExpMatch m in ms) {
        expect(m.group(1), isNot(contains('await')),
            reason: 'await between final check and mutation start');
      }
    });

    test('GithubBackupService: generic writes refuse reserved paths; '
        'authority writes need the grant and re-check before every '
        'mutating request', () {
      final String svc = code('core/github_backup_service.dart');
      expect(RegExp(r'GithubReservedPaths\.requireGenericWritable\(').allMatches(svc).length, 3);
      expect(svc, contains('required GithubAuthorityWriteGrant grant,'));
      expect(svc, contains('beforeRemoteMutation: grant.checkBeforeRequest'));
      expect('beforeRemoteMutation?.call();'.allMatches(svc).length, 7,
          reason: 'create PUT, tree, commit, ref-create, ref-update (single) '
              '+ commit, ref-update (multi)');
      // The check is never inside the _send closure (which swallows errors).
      expect(svc, isNot(contains('_send(() {\n')));
      final String prod = code('core/master_key_production_service.dart');
      expect(prod, contains('final class GithubAuthorityWriteGrant {'));
      expect(prod, contains('GithubAuthorityWriteGrant._('));
    });

    test('A: GithubBackupService is a final class; nothing in lib or test '
        'subclasses or implements it (no override can receive a grant)', () {
      expect(code('core/github_backup_service.dart'),
          contains('final class GithubBackupService {'));
      for (final String dir in <String>['lib', 'test']) {
        for (final FileSystemEntity f
            in Directory('${Directory.current.path}/$dir')
                .listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          // This audit names the forbidden constructs in string literals.
          if (f.path.endsWith('authority_remote_write_boundary_test.dart')) {
            continue;
          }
          final String text = f
              .readAsStringSync()
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n');
          expect(text, isNot(contains('extends GithubBackupService')),
              reason: f.path);
          expect(text, isNot(contains('implements GithubBackupService')),
              reason: f.path);
          expect(text, isNot(contains('with GithubBackupService')),
              reason: f.path);
        }
      }
    });

    test('B/C: grant scope and lifetime are enforced in the grant itself '
        '(kind, canonical path set, budget, expiry) and every issued grant '
        'is expired in a finally', () {
      final String prod = code('core/master_key_production_service.dart');
      final int g = prod.indexOf('final class GithubAuthorityWriteGrant {');
      final String grant = prod.substring(g, prod.indexOf('GithubAuthorityWriteGrant _newGrant('));
      expect(grant, contains('mutation kind is not permitted by this grant'));
      expect(grant, contains('path is not permitted by this grant'));
      expect(grant, contains('mutation budget of this grant is exhausted'));
      expect(grant, contains('grant expired'));
      expect(grant, contains('requireExactAuthorityTargets'));
      // every _newGrant( is paired with an _expire() in a finally
      final String all = prod + code('core/password_state_manager.dart');
      final int issued = 'final GithubAuthorityWriteGrant '.allMatches(all).length;
      final int expired = RegExp(r'finally \{\n\s*(createGrant|grant)\._expire\(\);')
          .allMatches(all)
          .length;
      expect(issued, greaterThanOrEqualTo(4));
      expect(expired, issued);
      // Scoped issuance: paths and kinds are explicit at every site.
      expect(all, contains('paths: <String>{fileName}'));
      expect(all, contains('paths: <String>{GithubReservedPaths.deviceKey, fileName}'));
      expect('maxMutations:'.allMatches(all).length, greaterThanOrEqualTo(4));
    });

    test('the authority methods open a scoped mutation and re-check the '
        'grant before every mutating request', () {
      final String svc = code('core/github_backup_service.dart');
      expect(svc, contains('grant.beginMutation(GithubAuthorityMutation.createFile'));
      expect(svc, contains('grant.beginMutation(GithubAuthorityMutation.updateFile,'));
      expect(svc, contains('grant.beginMutation(GithubAuthorityMutation.updateFiles,'));
      expect('grant.endMutation();'.allMatches(svc).length, 3);
      expect('beforeRemoteMutation: grant.checkBeforeRequest'.allMatches(svc).length, 3);
    });

    test('no HTTP request body/URL is built with an `await` inside a '
        'non-async callback (every async input is resolved BEFORE the final '
        'fence check, which sits in the same turn as the request start)', () {
      final String svc = _src('core/github_backup_service.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final RegExp call = RegExp(r'_client\.(get|put|post|patch)\(');
      for (final RegExpMatch m in call.allMatches(svc)) {
        final int end = svc.indexOf(');', m.end);
        final String args = svc.substring(m.end, end < 0 ? svc.length : end);
        expect(args, isNot(contains('await ')),
            reason: 'await inside _client.${m.group(1)}( arguments');
      }
      // The ref-creation path resolves the branch first, then checks, then sends.
      final int create = svc.indexOf('final String createBranch = await _effectiveBranchName();');
      final int check = svc.indexOf('beforeRemoteMutation?.call();', create);
      final int send = svc.indexOf('await _send(', check);
      expect(create, greaterThan(0));
      expect(check, greaterThan(create));
      expect(send, greaterThan(check));
      expect(svc.substring(check, send), isNot(contains('await')),
          reason: 'no suspension between the final check and the request start');
      expect(svc.substring(send, send + 200),
          contains("_apiSegments(const <String>['git', 'refs'])"));
    });

    test('A: percent-decoding fails closed when it cannot reach a fixed '
        'point, and the decode limit is documented', () {
      final String svc = code('core/github_backup_service.dart');
      expect(svc, contains('static const int maxDecodeLayers = 8;'));
      expect(svc, contains('if (round >= maxDecodeLayers) return null;'));
      final int n = svc.indexOf('static String? normalize(String path) {');
      final String body = svc.substring(n, svc.indexOf('static bool isReserved('));
      expect(body, contains('if (decoded == value) break;'),
          reason: 'only a stable (fully decoded) value is compared');
      final int decoding = body.indexOf('Uri.decodeComponent');
      final int separatorHandling = body.indexOf('value.replaceAll');
      expect(decoding, greaterThanOrEqualTo(0));
      expect(separatorHandling, greaterThan(decoding),
          reason: 'decode BEFORE separator handling');
    });

    test('B: the race-loss branch requires the exact persisted record, not '
        'just matching wrappers', () {
      final String prod = code('core/master_key_production_service.dart');
      expect(prod, contains('!local.isSamePersistedRecordAs(ownedLocal)'));
      expect(prod, isNot(contains('local.passwordWrap != ownedLocal.passwordWrap')));
      final String store = code('core/master_key_local_store.dart');
      final int i = store.indexOf('bool isSamePersistedRecordAs(');
      final String body = store.substring(i, i + 700);
      for (final String field in <String>[
        'schemaVersion', 'revision', 'authority', 'passwordVerifier',
        'passwordWrap', 'recoveryWrap', 'remoteRecoveryStatus',
        'repository', 'previousPublishedRecoveryWrap',
      ]) {
        expect(
            body.contains('$field ==') || body.contains('_blankToNull($field)'),
            isTrue,
            reason: field);
      }
    });

    test('no code outside the trusted library calls a GitHub write method',
        () {
      final Directory lib = Directory('${Directory.current.path}/lib');
      for (final FileSystemEntity f in lib.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String rel = f.path.substring(lib.path.length + 1).replaceAll('\\', '/');
        if (rel == 'core/github_backup_service.dart' ||
            rel == 'core/master_key_production_service.dart' ||
            rel == 'core/password_state_manager.dart') {
          continue;
        }
        final String text = code(rel);
        for (final String m in <String>[
          'createFileIfAbsent',
          'FileWithFastForwardCheck',
          'FilesWithFastForwardCheck',
          'authorityCreate',
          'GithubAuthorityWriteGrant._',
        ]) {
          expect(text, isNot(contains(m)), reason: '$rel calls $m');
        }
      }
    });

    test('checkpoint pause controls are gated by a compile-time define '
        'that nothing in the repository build config sets', () {
      final String cp = code('core/security_checkpoints.dart');
      expect(code('core/test_control.dart'),
          contains("bool.fromEnvironment('ROCEN_SECURITY_TEST_CHECKPOINTS')"));
      expect(cp, contains('kSecurityTestControlEnabled'));
      expect(cp, contains('static Future<void>? reach('));
      expect(cp, contains('if (!_enabled) return null;'));
      final Directory lib = Directory('${Directory.current.path}/lib');
      for (final FileSystemEntity f in lib.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String rel = f.path.substring(lib.path.length + 1).replaceAll('\\', '/');
        if (rel == 'core/security_checkpoints.dart' ||
            rel == 'core/test_control.dart') {
          continue;
        }
        final String text = f.readAsStringSync();
        final String executableText = text
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        expect(
            executableText, isNot(contains('ROCEN_SECURITY_TEST_CHECKPOINTS')),
            reason: rel);
        // Other production values (such as certificate pins) legitimately
        // use String.fromEnvironment. The checkpoint define is checked above
        // by its exact name and must remain confined to its control files.
        expect(text, isNot(contains('await SecurityCheckpoints.reach')),
            reason: '$rel: a production call site must not await a no-op');
        expect(text, isNot(contains('SecurityCheckpoints.arm(')), reason: rel);
        expect(text, isNot(contains('SecurityCheckpoints.release(')), reason: rel);
        expect(text, isNot(contains('SecurityCheckpoints.waitUntilPaused(')),
            reason: rel);
        expect(text, isNot(contains('SecurityCheckpoints.reset(')), reason: rel);
      }
      final String pubspec =
          File('${Directory.current.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('ROCEN_SECURITY_TEST_CHECKPOINTS')));
    });
  });
}
