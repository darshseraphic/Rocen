import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;

class GithubSyncException implements Exception {
  final String message;
  GithubSyncException(this.message);

  @override
  String toString() => message;
}

class GithubBackupService {
  final String token;
  final String repoPath;
  final String branch;

  GithubBackupService({
    required this.token,
    required this.repoPath,
    this.branch = 'main',
  });

  Uri _api(String path) => Uri.parse('https://api.github.com/repos/$repoPath$path');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<String?> _getBranchRefSha() async {
    final res = await http.get(_api('/git/ref/heads/$branch'), headers: _headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['object'] as Map<String, dynamic>)['sha'] as String;
    }
    if (res.statusCode == 404) return null;
    throw GithubSyncException('REF FETCH FAILED: ${res.statusCode} ${res.body}');
  }

  Future<String?> _getCommitTreeSha(String commitSha) async {
    final res = await http.get(_api('/git/commits/$commitSha'), headers: _headers);
    if (res.statusCode != 200) throw GithubSyncException('COMMIT FETCH FAILED: ${res.statusCode} ${res.body}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['tree'] as Map<String, dynamic>)['sha'] as String;
  }

  Future<String> _createTree({
    required List<Map<String, dynamic>> entries,
    String? baseTreeSha,
  }) async {
    final Map<String, dynamic> body = {'tree': entries};
    if (baseTreeSha != null) body['base_tree'] = baseTreeSha;

    final res = await http.post(_api('/git/trees'), headers: _headers, body: jsonEncode(body));
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

  Future<String> _createRootCommit({required String treeSha, required String message}) async {
    final res = await http.post(
      _api('/git/commits'),
      headers: _headers,
      body: jsonEncode({'message': message, 'tree': treeSha, 'parents': <String>[]}),
    );
    if (res.statusCode != 201) throw GithubSyncException('COMMIT CREATE FAILED: ${res.statusCode} ${res.body}');
    return (jsonDecode(res.body) as Map<String, dynamic>)['sha'] as String;
  }

  Future<void> _forcePushRef(String commitSha, {required bool refExists}) async {
    if (refExists) {
      final res = await http.patch(
        _api('/git/refs/heads/$branch'),
        headers: _headers,
        body: jsonEncode({'sha': commitSha, 'force': true}),
      );
      if (res.statusCode != 200) throw GithubSyncException('REF UPDATE FAILED: ${res.statusCode} ${res.body}');
    } else {
      final res = await http.post(
        _api('/git/refs'),
        headers: _headers,
        body: jsonEncode({'ref': 'refs/heads/$branch', 'sha': commitSha}),
      );
      if (res.statusCode != 201) throw GithubSyncException('REF CREATE FAILED: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> amendSync({
    Map<String, String> upsertFiles = const {},
    List<String> deleteFiles = const [],
    Map<String, String> renameFiles = const {},
    String message = 'rocen sync',
  }) async {
    if (upsertFiles.isEmpty && deleteFiles.isEmpty && renameFiles.isEmpty) return;

    final currentRefSha = await _getBranchRefSha();
    final String? baseTreeSha = currentRefSha != null ? await _getCommitTreeSha(currentRefSha) : null;

    final Set<String> existingFiles = (currentRefSha != null && (deleteFiles.isNotEmpty || renameFiles.isNotEmpty))
        ? (await listNoteFiles()).toSet()
        : <String>{};

    final List<String> validDeleteFiles = deleteFiles.where(existingFiles.contains).toList();
    final Map<String, String> validRenameFiles = Map.fromEntries(
      renameFiles.entries.where((entry) => existingFiles.contains(entry.key)),
    );

    final List<Map<String, dynamic>> entries = [];

    for (final path in validDeleteFiles) {
      entries.add({'path': path, 'mode': '100644', 'type': 'blob', 'sha': null});
    }

    validRenameFiles.forEach((oldPath, newPath) {
      entries.add({'path': oldPath, 'mode': '100644', 'type': 'blob', 'sha': null});
      if (!upsertFiles.containsKey(newPath)) {
        entries.add({'path': newPath, 'mode': '100644', 'type': 'blob', 'content': upsertFiles[newPath] ?? ''});
      }
    });

    upsertFiles.forEach((path, content) {
      entries.add({'path': path, 'mode': '100644', 'type': 'blob', 'content': content});
    });

    if (entries.isEmpty) return;

    final newTreeSha = await _createTree(entries: entries, baseTreeSha: baseTreeSha);
    final newCommitSha = await _createRootCommit(treeSha: newTreeSha, message: message);

    await _forcePushRef(newCommitSha, refExists: currentRefSha != null);
  }

  Future<Map<String, dynamic>?> fetchNoteFile(String fileName) async {
    final res = await http.get(_api('/contents/$fileName'), headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw GithubSyncException('FILE FETCH FAILED: ${res.statusCode} ${res.body}');

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final String encodedContent = (data['content'] as String).replaceAll('\n', '');
    final String rawJson = utf8.decode(base64.decode(encodedContent));
    return jsonDecode(rawJson) as Map<String, dynamic>;
  }

  Future<List<String>> listNoteFiles() async {
    final res = await http.get(_api('/contents'), headers: _headers);
    debugPrint('LIST NOTE FILES: status=${res.statusCode}');
    if (res.statusCode == 404) return [];
    if (res.statusCode != 200) throw GithubSyncException('DIRECTORY LIST FAILED: ${res.statusCode} ${res.body}');

    final dynamic decoded = jsonDecode(res.body);
    if (decoded is! List) {
      debugPrint('LIST NOTE FILES: response was not a List, raw body: ${res.body}');
      return [];
    }

    final List<String> names = decoded
        .where((e) => e['type'] == 'file' && (e['name'] as String).endsWith('.json'))
        .map((e) => e['name'] as String)
        .toList();
    debugPrint('LIST NOTE FILES: found ${decoded.length} entries total, ${names.length} .json files: $names');
    return names;
  }
}