import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rocen/core/github_backup_service.dart';

class _Branch {
  String? sha;
  final Map<String, String> files = <String, String>{};
}

/// TRANSPORT-level fake of the GitHub REST endpoints that
/// [GithubBackupService] uses. Tests hand the REAL (final) service this
/// fake's `http.Client`, so the real request/response code runs, every
/// authority-grant check runs, and no test-controlled code ever receives a
/// production grant (the transport sees HTTP requests only).
///
/// Models a repository with several BRANCHES (one is the default branch),
/// commits and trees (ids are 40-hex like GitHub's), the contents API
/// (GET/PUT) and git trees/commits/refs (POST/PATCH) with fast-forward
/// rejection. Reads and writes are logged per branch so tests can assert that
/// every request of an operation targeted the same branch.
///
/// Pinned reads are STRICT: a non-null `ref` resolves to an existing branch
/// name, the exact current head commit of a branch, or a recorded historical
/// commit snapshot - anything else is a 404, never the current content.
class FakeGithubRemote {
  FakeGithubRemote(
      {this.repoPath = 'owner/repo', this.defaultBranch = 'main'}) {
    client = MockClient(_handle);
  }

  final String repoPath;
  String defaultBranch;
  late final http.Client client;

  /// Explicit branch = default branch (what older tests assume).
  late final GithubBackupService service = serviceFor(branch: defaultBranch);

  /// Implicit branch selection - what production Settings does.
  late final GithubBackupService implicitService = serviceFor();

  GithubBackupService serviceFor({String? branch}) => GithubBackupService(
        token: 'test-token',
        repoPath: repoPath,
        branch: branch,
        client: client,
      );

  final Map<String, _Branch> _branches = <String, _Branch>{};

  _Branch get _def => _branches.putIfAbsent(defaultBranch, () => _Branch());

  /// Default branch head content (path -> raw JSON text).
  Map<String, String> get files => _def.files;

  /// Default branch head commit; null = empty repository.
  String? get branchSha => _def.sha;
  set branchSha(String? value) {
    _def.sha = value;
    if (value != null) _record(value, defaultBranch, _def.files);
  }

  bool failCreateOnce = false;
  bool failPasswordStateUpdateOnce = false;
  void Function(String path)? onContentsCreate;

  /// When set, the NEXT contents PUT loses a remote-initialization race: this
  /// content appears as the file just before the PUT and the PUT is answered
  /// 422 (already exists).
  String? raceWinnerContent;
  bool raceWinnerUsesAttemptedContent = false;

  /// Every mutating request, "METHOD /relative/path".
  final List<String> mutationLog = <String>[];

  /// Every file path any mutating request attempted to write.
  final List<String> writtenPaths = <String>[];

  /// Branch NAME each mutating request targeted (contents PUT `branch`, git
  /// ref create/update path).
  final List<String> mutationBranches = <String>[];

  /// For every created commit: the branch each parent commit belongs to.
  final List<String?> commitParentBranches = <String?>[];

  /// Current content of [name] (null if the branch does not exist).
  Map<String, String>? branchFiles(String name) {
    final _Branch? b = _branches[name];
    return (b == null || b.sha == null)
        ? null
        : Map<String, String>.from(b.files);
  }

  /// Branch NAME of every `GET /git/ref/heads/<name>`.
  final List<String> refReads = <String>[];

  /// "METHOD <decoded path> ref=<ref|->" for every Contents request.
  final List<String> contentsRequests = <String>[];

  /// For every Contents request: the branch the answer came from, or null.
  final List<String?> contentsReadBranches = <String?>[];

  /// The ENCODED path exactly as sent, and the number of path segments.
  final List<String> rawContentsPaths = <String>[];
  final List<int> contentsSegmentCounts = <int>[];

  /// Requests whose path was NOT under /repos/<repoPath>.
  final List<String> unroutedRequests = <String>[];

  int requestCount = 0;
  int get mutationCount => mutationLog.length;

  int _n = 0;
  bool _everHadCommit = false;
  final Map<String, Map<String, String>> _history =
      <String, Map<String, String>>{};
  final Map<String, String> _shaBranch = <String, String>{};
  final Map<String, Map<String, String>> _trees =
      <String, Map<String, String>>{};
  final Map<String, ({String tree, List<String> parents})> _commits =
      <String, ({String tree, List<String> parents})>{};

  /// Which branch a commit id belongs to (or null).
  String? branchOfSha(String sha) => _shaBranch[sha];

  String _hex() => (++_n).toRadixString(16).padLeft(40, '0');

  void _record(String sha, String branch, Map<String, String> files) {
    _history[sha] = Map<String, String>.from(files);
    _shaBranch[sha] = branch;
  }

  /// Creates (or replaces the head of) an extra branch with [content].
  void addBranch(String name, Map<String, String> content) {
    final _Branch b = _branches.putIfAbsent(name, () => _Branch());
    b.files
      ..clear()
      ..addAll(content);
    b.sha = _hex();
    _everHadCommit = true;
    _record(b.sha!, name, b.files);
  }

  void removeBranch(String name) => _branches.remove(name);

  void seed(String path, String content) {
    files[path] = content;
    _def.sha ??= _hex();
    _everHadCommit = true;
    _record(_def.sha!, defaultBranch, _def.files);
  }

  http.Response _json(Object body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );

  /// Content visible at [ref] (branch name, current head sha, or recorded
  /// historical sha). Unknown -> null (caller answers 404). Also sets
  /// [branchOut].
  Map<String, String>? _view(String ref, void Function(String?) branchOut) {
    final _Branch? byName = _branches[ref];
    if (byName != null && byName.sha != null) {
      branchOut(ref);
      return byName.files;
    }
    for (final MapEntry<String, _Branch> e in _branches.entries) {
      if (e.value.sha == ref) {
        branchOut(e.key);
        return e.value.files; // exact CURRENT head commit
      }
    }
    final Map<String, String>? hist = _history[ref];
    if (hist != null) {
      branchOut(_shaBranch[ref]);
      return hist;
    }
    return null; // unknown ref: NEVER current content
  }

  String _treeIdFor(Map<String, String> snapshot) {
    final String id = _hex();
    _trees[id] = Map<String, String>.from(snapshot);
    return id;
  }

  Future<http.Response> _handle(http.Request request) async {
    final List<String> repoSegments = repoPath.split('/');
    final List<String> segs = request.url.pathSegments;
    final bool inRepo = segs.length >= 1 + repoSegments.length &&
        segs.first == 'repos' &&
        List<String>.generate(repoSegments.length, (i) => segs[1 + i])
                .join('/') ==
            repoPath;
    if (!inRepo) unroutedRequests.add(request.url.toString());
    final String path = inRepo
        ? (segs.length == 1 + repoSegments.length
            ? ''
            : '/${segs.sublist(1 + repoSegments.length).join('/')}')
        : request.url.path;
    final String method = request.method;
    requestCount++;
    final Map<String, dynamic> body = request.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(request.body) as Map<String, dynamic>);

    if (method != 'GET') mutationLog.add('$method $path');

    if (method == 'GET' && path.isEmpty) {
      return _json(<String, dynamic>{
        'full_name': repoPath,
        'default_branch': defaultBranch,
        'size': _everHadCommit ? 1 : 0,
        'pushed_at': _everHadCommit ? '2026-01-01T00:00:00Z' : null,
        'permissions': <String, dynamic>{'pull': true, 'push': true},
      }, 200);
    }
    if (method == 'GET' && path == '/branches') {
      final List<String> names = _branches.entries
          .where((e) => e.value.sha != null)
          .map((e) => e.key)
          .take(int.tryParse(request.url.queryParameters['per_page'] ?? '30') ??
              30)
          .toList();
      return _json(
          names.map((name) => <String, dynamic>{'name': name}).toList(), 200);
    }
    if (method == 'GET' && path.startsWith('/git/ref/heads/')) {
      final String name = path.substring('/git/ref/heads/'.length);
      refReads.add(name);
      final _Branch? b = _branches[name];
      if (b == null || b.sha == null) return _json(<String, dynamic>{}, 404);
      return _json(<String, dynamic>{
        'object': <String, dynamic>{'sha': b.sha},
      }, 200);
    }
    if (method == 'GET' && path.startsWith('/git/commits/')) {
      final String sha = path.substring('/git/commits/'.length);
      final String? tree = _commits[sha]?.tree;
      if (tree != null) {
        return _json(<String, dynamic>{
          'tree': <String, dynamic>{'sha': tree},
        }, 200);
      }
      final Map<String, String>? view = _view(sha, (_) {});
      if (view == null) return _json(<String, dynamic>{}, 404);
      return _json(<String, dynamic>{
        'tree': <String, dynamic>{'sha': _treeIdFor(view)},
      }, 200);
    }
    if (path.startsWith('/contents/')) {
      rawContentsPaths.add(request.url.path);
      contentsSegmentCounts.add(segs.length);
      contentsRequests.add('$method ${path.substring('/contents/'.length)} '
          'ref=${request.url.queryParameters['ref'] ?? '-'}');
    }
    if (method == 'GET' && path.startsWith('/contents/')) {
      final String file = path.substring('/contents/'.length);
      final String? ref = request.url.queryParameters['ref'];
      String? readBranch;
      final Map<String, String>? view = ref == null
          ? _view(defaultBranch, (b) => readBranch = b) // unpinned: default
          : _view(ref, (b) => readBranch = b);
      contentsReadBranches.add(readBranch);
      if (view == null) return _json(<String, dynamic>{}, 404);
      final String? raw = view[file];
      if (raw == null) return _json(<String, dynamic>{}, 404);
      return _json(<String, dynamic>{
        'content': base64Encode(utf8.encode(raw)),
      }, 200);
    }
    if (method == 'PUT' && path.startsWith('/contents/')) {
      final String file = path.substring('/contents/'.length);
      final String target = (body['branch'] as String?) ?? defaultBranch;
      mutationBranches.add(target);
      writtenPaths.add(file);
      _Branch? b = _branches[target];
      if (b == null || b.sha == null) {
        // GitHub creates the branch only in an EMPTY repository.
        final bool repoEmpty =
            _branches.values.every((_Branch x) => x.sha == null);
        if (!repoEmpty) return _json(<String, dynamic>{}, 404);
        b = _branches.putIfAbsent(target, () => _Branch());
      }
      if (raceWinnerContent != null && !b.files.containsKey(file)) {
        b.files[file] = raceWinnerUsesAttemptedContent
            ? utf8.decode(base64Decode(body['content'] as String))
            : raceWinnerContent!;
        raceWinnerContent = null;
        raceWinnerUsesAttemptedContent = false;
        b.sha ??= _hex();
        _record(b.sha!, target, b.files);
        return _json(<String, dynamic>{}, 422);
      }
      if (failCreateOnce) {
        failCreateOnce = false;
        return _json(<String, dynamic>{}, 500);
      }
      if (b.files.containsKey(file)) return _json(<String, dynamic>{}, 422);
      b.files[file] = utf8.decode(base64Decode((body['content'] as String)));
      b.sha = _hex();
      _record(b.sha!, target, b.files);
      onContentsCreate?.call(file);
      return _json(<String, dynamic>{
        'content': <String, dynamic>{},
        'commit': <String, dynamic>{},
      }, 201);
    }
    if (method == 'POST' && path == '/git/trees') {
      final String? base = body['base_tree'] as String?;
      final Map<String, String> next = base == null
          ? <String, String>{}
          : Map<String, String>.from(_trees[base] ?? <String, String>{});
      for (final dynamic e in body['tree'] as List<dynamic>) {
        final Map<String, dynamic> entry = e as Map<String, dynamic>;
        writtenPaths.add(entry['path'] as String);
        next[entry['path'] as String] = entry['content'] as String;
      }
      return _json(<String, dynamic>{'sha': _treeIdFor(next)}, 201);
    }
    if (method == 'POST' && path == '/git/commits') {
      final String id = _hex();
      _commits[id] = (
        tree: body['tree'] as String,
        parents: List<String>.from(body['parents'] as List<dynamic>),
      );
      for (final String parent in _commits[id]!.parents) {
        commitParentBranches.add(_shaBranch[parent]);
      }
      return _json(<String, dynamic>{'sha': id}, 201);
    }
    if (method == 'POST' && path == '/git/refs') {
      final String ref = body['ref'] as String;
      final String name = ref.substring('refs/heads/'.length);
      mutationBranches.add(name);
      final _Branch? existing = _branches[name];
      if (existing != null && existing.sha != null) {
        return _json(<String, dynamic>{}, 422);
      }
      final String sha = body['sha'] as String;
      final _Branch b = _branches.putIfAbsent(name, () => _Branch());
      b.files
        ..clear()
        ..addAll(_trees[_commits[sha]!.tree] ?? <String, String>{});
      b.sha = sha;
      _record(sha, name, b.files);
      return _json(<String, dynamic>{}, 201);
    }
    if (method == 'PATCH' && path.startsWith('/git/refs/heads/')) {
      final String name = path.substring('/git/refs/heads/'.length);
      mutationBranches.add(name);
      final _Branch? b = _branches[name];
      if (b == null || b.sha == null) return _json(<String, dynamic>{}, 404);
      final String sha = body['sha'] as String;
      final commit = _commits[sha];
      if (commit == null || !commit.parents.contains(b.sha)) {
        return _json(<String, dynamic>{}, 422);
      }
      final Map<String, String> snapshot =
          Map<String, String>.from(_trees[commit.tree] ?? <String, String>{});
      if (failPasswordStateUpdateOnce &&
          snapshot['password_state.json'] != b.files['password_state.json']) {
        failPasswordStateUpdateOnce = false;
        return _json(<String, dynamic>{}, 500);
      }
      b.files
        ..clear()
        ..addAll(snapshot);
      b.sha = sha;
      _record(sha, name, b.files);
      return _json(<String, dynamic>{}, 200);
    }
    return _json(<String, dynamic>{'unhandled': '$method $path'}, 500);
  }
}
