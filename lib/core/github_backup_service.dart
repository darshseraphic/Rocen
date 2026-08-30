import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import 'cert_pinning.dart';

class GithubSyncException implements Exception {
  final String message;
  GithubSyncException(this.message);

  @override
  String toString() => message;
}

/// Thrown by [GithubBackupService.updateFileWithFastForwardCheck] when
/// the branch moved between the caller's last read and this write
/// attempt. This means another writer committed first — the caller
/// should re-fetch the current file and re-evaluate (e.g. re-run the
/// generation/changeId comparison) rather than blindly retry the same
/// write, since the content it was about to write may no longer be
/// correct given what the other writer just committed.
class GithubConditionalWriteConflict implements Exception {
  final String message;
  GithubConditionalWriteConflict(this.message);

  @override
  String toString() => 'GithubConditionalWriteConflict: $message';
}

class GithubBackupService {
  final String token;
  final String repoPath;
  final String branch;
  final http.Client _client = CertPinning.createPinnedClient();

  GithubBackupService({
    required this.token,
    required this.repoPath,
    this.branch = 'main',
  });
  void dispose() {
    _client.close();
  }

  Uri _api(String path) =>
      Uri.parse('https://api.github.com/repos/$repoPath$path');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<String?> _getBranchRefSha() async {
    final res =
        await _client.get(_api('/git/ref/heads/$branch'), headers: _headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['object'] as Map<String, dynamic>)['sha'] as String;
    }
    if (res.statusCode == 404) return null;
    throw GithubSyncException(
        'REF FETCH FAILED: ${res.statusCode} ${res.body}');
  }

  Future<String?> _getCommitTreeSha(String commitSha) async {
    final res =
        await _client.get(_api('/git/commits/$commitSha'), headers: _headers);
    if (res.statusCode != 200)
      throw GithubSyncException(
          'COMMIT FETCH FAILED: ${res.statusCode} ${res.body}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['tree'] as Map<String, dynamic>)['sha'] as String;
  }

  Future<String> _createTree({
    required List<Map<String, dynamic>> entries,
    String? baseTreeSha,
  }) async {
    final Map<String, dynamic> body = {'tree': entries};
    if (baseTreeSha != null) body['base_tree'] = baseTreeSha;

    final res = await _client.post(_api('/git/trees'),
        headers: _headers, body: jsonEncode(body));
    if (res.statusCode != 201) {
      final String entrySummary = entries
          .map((e) => '${e['path']}:${e['sha'] == null ? 'DELETE' : 'UPSERT'}')
          .join(', ');
      throw GithubSyncException(
        'TREE CREATE FAILED: ${res.statusCode} ${res.body} | base_tree=$baseTreeSha | entries=[$entrySummary]',
      );
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['sha'] as String;
  }

  Future<String> _createRootCommit(
      {required String treeSha, required String message}) async {
    final res = await _client.post(
      _api('/git/commits'),
      headers: _headers,
      body: jsonEncode(
          {'message': message, 'tree': treeSha, 'parents': <String>[]}),
    );
    if (res.statusCode != 201)
      throw GithubSyncException(
          'COMMIT CREATE FAILED: ${res.statusCode} ${res.body}');
    return (jsonDecode(res.body) as Map<String, dynamic>)['sha'] as String;
  }

  Future<void> _forcePushRef(String commitSha,
      {required bool refExists}) async {
    if (refExists) {
      final res = await _client.patch(
        _api('/git/refs/heads/$branch'),
        headers: _headers,
        body: jsonEncode({'sha': commitSha, 'force': true}),
      );
      if (res.statusCode != 200)
        throw GithubSyncException(
            'REF UPDATE FAILED: ${res.statusCode} ${res.body}');
    } else {
      final res = await _client.post(
        _api('/git/refs'),
        headers: _headers,
        body: jsonEncode({'ref': 'refs/heads/$branch', 'sha': commitSha}),
      );
      if (res.statusCode != 201)
        throw GithubSyncException(
            'REF CREATE FAILED: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> amendSync({
    Map<String, String> upsertFiles = const {},
    List<String> deleteFiles = const [],
    Map<String, String> renameFiles = const {},
    String message = 'rocen sync',
  }) async {
    if (upsertFiles.isEmpty && deleteFiles.isEmpty && renameFiles.isEmpty)
      return;

    final currentRefSha = await _getBranchRefSha();
    final String? baseTreeSha =
        currentRefSha != null ? await _getCommitTreeSha(currentRefSha) : null;

    final Set<String> existingFiles = (currentRefSha != null &&
            (deleteFiles.isNotEmpty || renameFiles.isNotEmpty))
        ? (await listNoteFiles()).toSet()
        : <String>{};

    final List<String> validDeleteFiles =
        deleteFiles.where(existingFiles.contains).toList();
    final Map<String, String> validRenameFiles = Map.fromEntries(
      renameFiles.entries.where((entry) => existingFiles.contains(entry.key)),
    );

    final List<Map<String, dynamic>> entries = [];

    for (final path in validDeleteFiles) {
      entries
          .add({'path': path, 'mode': '100644', 'type': 'blob', 'sha': null});
    }

    validRenameFiles.forEach((oldPath, newPath) {
      entries.add(
          {'path': oldPath, 'mode': '100644', 'type': 'blob', 'sha': null});
      if (!upsertFiles.containsKey(newPath)) {
        entries.add({
          'path': newPath,
          'mode': '100644',
          'type': 'blob',
          'content': upsertFiles[newPath] ?? ''
        });
      }
    });

    upsertFiles.forEach((path, content) {
      entries.add(
          {'path': path, 'mode': '100644', 'type': 'blob', 'content': content});
    });

    if (entries.isEmpty) return;

    final newTreeSha =
        await _createTree(entries: entries, baseTreeSha: baseTreeSha);
    final newCommitSha =
        await _createRootCommit(treeSha: newTreeSha, message: message);

    await _forcePushRef(newCommitSha, refExists: currentRefSha != null);
  }

  /// Like [fetchNoteFile], but also returns the branch ref SHA observed
  /// at the moment of the read — the exact value a caller must pass as
  /// `expectedParentSha` to [updateFileWithFastForwardCheck] afterward,
  /// so the eventual write is conditioned on the same state this read
  /// saw. Returns null content if the file doesn't exist yet; the ref
  /// SHA is still returned (it may be null too, if the branch itself
  /// doesn't exist yet).
  ///
  /// NOTE: the ref-SHA read and the file-content read are two separate
  /// HTTP calls, not one atomic operation — there is a small window
  /// between them where the branch could move. This does not weaken the
  /// eventual write's safety: updateFileWithFastForwardCheck re-checks
  /// the ref SHA again immediately before writing, so a race in this
  /// window still results in a correctly-rejected write, not a silent
  /// overwrite. It only means the `content` returned here could, in a
  /// narrow window, be very slightly stale relative to `refSha` — the
  /// caller's subsequent write attempt is what actually enforces safety.
  Future<({Map<String, dynamic>? content, String? refSha})>
      fetchNoteFileWithRefSha(String fileName) async {
    final String? refSha = await _getBranchRefSha();
    final Map<String, dynamic>? content = await fetchNoteFile(fileName);
    return (content: content, refSha: refSha);
  }

  Future<Map<String, dynamic>?> fetchNoteFile(String fileName) async {
    final res =
        await _client.get(_api('/contents/$fileName'), headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200)
      throw GithubSyncException(
          'FILE FETCH FAILED: ${res.statusCode} ${res.body}');

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final String encodedContent =
        (data['content'] as String).replaceAll('\n', '');
    final String rawJson = utf8.decode(base64.decode(encodedContent));
    return jsonDecode(rawJson) as Map<String, dynamic>;
  }

  /// Genuine conditional write, distinct from [amendSync]'s force-push
  /// model. [amendSync] always builds a PARENTLESS root commit
  /// (`parents: []`) and force-pushes it — by construction that can
  /// never be a fast-forward of anything, which is why it always needs
  /// `force: true`. This method does the opposite: it builds a commit
  /// whose PARENT is the exact ref SHA this client read, and pushes with
  /// `force: false`. If another writer moved the branch in between,
  /// this client's commit is no longer a fast-forward of the branch's
  /// actual current tip, and GitHub's ref-update endpoint rejects the
  /// write atomically, server-side — the caller gets
  /// [GithubConditionalWriteConflict] instead of silently overwriting
  /// whatever the other writer committed.
  ///
  /// This is intentionally used for `password_state.json` ONLY. It is
  /// not a replacement for [amendSync]'s note-sync behavior, which is
  /// unchanged and still uses the existing force-push model.
  ///
  /// Returns normally on success. Throws
  /// [GithubConditionalWriteConflict] if the branch moved since
  /// `expectedParentSha` was read (the caller should re-fetch the file
  /// and re-evaluate before deciding whether to retry). Throws
  /// [GithubSyncException] for other failures (network, auth, etc).
  Future<void> updateFileWithFastForwardCheck({
    required String path,
    required String content,
    required String message,
    required String? expectedParentSha,
  }) async {
    final String? currentRefSha = await _getBranchRefSha();

    // If the ref moved (or came into existence) since the caller last
    // read it, refuse before even attempting a write — this catches the
    // common case cheaply, without waiting on GitHub's own
    // fast-forward rejection for it.
    if (currentRefSha != expectedParentSha) {
      throw GithubConditionalWriteConflict(
          'branch moved: expected parent $expectedParentSha, actual $currentRefSha');
    }

    final String? baseTreeSha =
        currentRefSha != null ? await _getCommitTreeSha(currentRefSha) : null;

    final String newTreeSha = await _createTree(
      entries: [
        {'path': path, 'mode': '100644', 'type': 'blob', 'content': content},
      ],
      baseTreeSha: baseTreeSha,
    );

    // Unlike _createRootCommit (used by amendSync), this commit has a
    // REAL parent — the exact ref SHA this client observed — which is
    // what makes the upcoming non-force ref update a genuine
    // fast-forward check rather than an unconditional overwrite.
    final Map<String, dynamic> commitBody = {
      'message': message,
      'tree': newTreeSha,
      'parents': currentRefSha != null ? [currentRefSha] : <String>[],
    };
    final commitRes = await _client.post(
      _api('/git/commits'),
      headers: _headers,
      body: jsonEncode(commitBody),
    );
    if (commitRes.statusCode != 201) {
      throw GithubSyncException(
          'CONDITIONAL COMMIT CREATE FAILED: ${commitRes.statusCode} ${commitRes.body}');
    }
    final String newCommitSha =
        (jsonDecode(commitRes.body) as Map<String, dynamic>)['sha'] as String;

    if (currentRefSha == null) {
      // Branch/ref doesn't exist yet — create it. There's nothing to
      // fast-forward from, so this is the one case with no race to
      // guard against (the ref either gets created by us or by someone
      // else first; a 422 here means someone else won that race).
      final createRes = await _client.post(
        _api('/git/refs'),
        headers: _headers,
        body: jsonEncode({'ref': 'refs/heads/$branch', 'sha': newCommitSha}),
      );
      if (createRes.statusCode == 422) {
        throw GithubConditionalWriteConflict(
            'branch was created by another writer before this ref-create landed');
      }
      if (createRes.statusCode != 201) {
        throw GithubSyncException(
            'CONDITIONAL REF CREATE FAILED: ${createRes.statusCode} ${createRes.body}');
      }
      return;
    }

    // The actual conditional step: force: false means GitHub will only
    // accept this if newCommitSha's parent (currentRefSha) is still the
    // branch's current tip. If another writer already moved the branch,
    // this is not a fast-forward and GitHub rejects it.
    final updateRes = await _client.patch(
      _api('/git/refs/heads/$branch'),
      headers: _headers,
      body: jsonEncode({'sha': newCommitSha, 'force': false}),
    );

    if (updateRes.statusCode == 422 || updateRes.statusCode == 409) {
      throw GithubConditionalWriteConflict(
          'REF UPDATE REJECTED (not a fast-forward - branch moved): ${updateRes.statusCode} ${updateRes.body}');
    }
    if (updateRes.statusCode != 200) {
      throw GithubSyncException(
          'CONDITIONAL REF UPDATE FAILED: ${updateRes.statusCode} ${updateRes.body}');
    }
  }

  Future<List<String>> listNoteFiles() async {
    final res = await _client.get(_api('/contents'), headers: _headers);
    debugPrint('LIST NOTE FILES: status=${res.statusCode}');
    if (res.statusCode == 404) return [];
    if (res.statusCode != 200)
      throw GithubSyncException(
          'DIRECTORY LIST FAILED: ${res.statusCode} ${res.body}');

    final dynamic decoded = jsonDecode(res.body);
    if (decoded is! List) {
      debugPrint(
          'LIST NOTE FILES: response was not a List, raw body: ${res.body}');
      return [];
    }

    final List<String> names = decoded
        .where((e) =>
            e['type'] == 'file' && (e['name'] as String).endsWith('.json'))
        .map((e) => e['name'] as String)
        .toList();
    debugPrint(
        'LIST NOTE FILES: found ${decoded.length} entries total, ${names.length} .json files: $names');
    return names;
  }
}
