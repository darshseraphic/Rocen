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

class GithubConditionalWriteConflict implements Exception {
  final String message;

  GithubConditionalWriteConflict(this.message);

  @override
  String toString() => 'GithubConditionalWriteConflict: $message';
}

class GithubFileAlreadyExists implements Exception {
  final String message;

  GithubFileAlreadyExists(this.message);

  @override
  String toString() => 'GithubFileAlreadyExists: $message';
}

class GithubBackupService {
  final String token;
  final String repoPath;
  final String branch;

  final http.Client _client = CertPinning.client;

  String? _resolvedBranch;
  bool _repositoryMetadataValidated = false;

  GithubBackupService({
    required this.token,
    required this.repoPath,
    this.branch = 'main',
  });

  void dispose() {}

  Uri _api(String path) {
    _validateRepoPath();
    return Uri.parse('https://api.github.com/repos/$repoPath$path');
  }

  void _validateRepoPath() {
    final String value = repoPath.trim();
    final bool valid = RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(value);
    if (!valid) {
      throw GithubSyncException(
        'INVALID GITHUB REPOSITORY: expected owner/repository, for example username/repo.',
      );
    }
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'Rocen/${'0.4.0'}',
        'X-GitHub-Api-Version': '2026-03-10',
      };
  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request();
    } on http.ClientException catch (e) {
      throw GithubSyncException(
        'SECURE CONNECTION FAILED: ${e.message}',
      );
    }
  }

  GithubSyncException _permissionDenied(
    http.Response res, {
    required String operation,
    String? documentedPermission,
    bool repositoryAccessAlreadyValidated = false,
  }) {
    final String body = res.body.trim();
    final String bodyLower = body.toLowerCase();

    if (bodyLower.contains('rate limit') ||
        bodyLower.contains('api rate limit exceeded')) {
      return GithubSyncException(
        'GITHUB API RATE LIMIT REACHED while $operation: GitHub temporarily '
        'refused this request. Please try again later.',
      );
    }

    final String permissionText = documentedPermission == null
        ? ''
        : ' This GitHub endpoint normally requires $documentedPermission.';

    final String accessText = repositoryAccessAlreadyValidated
        ? ' GitHub repository metadata was successfully checked earlier, so the token reached the requested repository; this specific operation was denied.'
        : ' This failure was reported directly by the requested GitHub operation; repository metadata access was not assumed.';

    return GithubSyncException(
      'GITHUB TOKEN PERMISSION DENIED while $operation (HTTP 403).$accessText'
      '$permissionText Check the token repository selection and repository permissions.\n\n'
      'GitHub response: $body',
    );
  }

  Future<void> validateRepositoryAccess() async {
    _repositoryMetadataValidated = false;

    final res = await _send(
      () => _client.get(
        _api(''),
        headers: _headers,
      ),
    );

    if (res.statusCode == 401) {
      throw GithubSyncException(
        'GITHUB TOKEN REJECTED while checking repository access (HTTP 401). '
        'The token may be invalid, expired, revoked, or otherwise rejected by GitHub.\n\n'
        'GitHub response: ${res.body}',
      );
    }

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'checking repository metadata for "$repoPath"',
        documentedPermission: 'metadata=read',
      );
    }

    if (res.statusCode == 404) {
      throw GithubSyncException(
        'GITHUB REPOSITORY NOT FOUND OR NOT AUTHORIZED (HTTP 404) for "$repoPath". '
        'Verify that the exact repository is selected for the fine-grained token.\n\n'
        'GitHub response: ${res.body}',
      );
    }

    if (res.statusCode != 200) {
      throw GithubSyncException(
        'REPOSITORY ACCESS FAILED for "$repoPath": HTTP ${res.statusCode}.\n\n'
        'GitHub response: ${res.body}',
      );
    }

    final dynamic decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw GithubSyncException(
        'REPOSITORY ACCESS FAILED: GitHub returned an invalid repository response.',
      );
    }

    final String fullName = (decoded['full_name'] ?? '').toString().trim();
    if (fullName.isEmpty) {
      throw GithubSyncException(
        'REPOSITORY ACCESS FAILED: GitHub did not return the repository name.',
      );
    }

    if (fullName.toLowerCase() != repoPath.toLowerCase()) {
      throw GithubSyncException(
        'REPOSITORY ACCESS FAILED: GitHub resolved "$repoPath" to "$fullName". '
        'Check the repository name entered in Rocen.',
      );
    }

    final String defaultBranch =
        (decoded['default_branch'] ?? '').toString().trim();
    if (defaultBranch.isNotEmpty) {
      _resolvedBranch = defaultBranch;
    }

    final dynamic permissions = decoded['permissions'];
    final bool? canPull =
        permissions is Map<String, dynamic> && permissions.containsKey('pull')
            ? permissions['pull'] == true
            : null;
    final bool? canPush =
        permissions is Map<String, dynamic> && permissions.containsKey('push')
            ? permissions['push'] == true
            : null;

    debugPrint(
      'GITHUB ACCESS OK: fullName=$fullName '
      'pull=${canPull ?? 'unknown'} push=${canPush ?? 'unknown'}',
    );

    _repositoryMetadataValidated = true;

    if (canPush == false) {
      throw GithubSyncException(
        'GITHUB REPOSITORY ACCESS IS READ-ONLY for "$repoPath". '
        'GitHub can see the repository, but the token has no effective push '
        'permission. Rocen backup requires repository Contents write access.\n\n'
        'GitHub response: ${res.body}',
      );
    }
  }

  Future<String?> _getRepositoryDefaultBranch() async {
    final res = await _send(
      () => _client.get(
        _api(''),
        headers: _headers,
      ),
    );

    if (res.statusCode == 401) {
      throw GithubSyncException(
        'GITHUB TOKEN REJECTED while checking repository access (HTTP 401). '
        'The token may be invalid, expired, revoked, or otherwise rejected by GitHub.\n\n'
        'GitHub response: ${res.body}',
      );
    }

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'checking repository access',
        documentedPermission: 'metadata=read',
      );
    }

    if (res.statusCode == 404) {
      throw GithubSyncException(
        'GITHUB REPOSITORY NOT FOUND OR NOT AUTHORIZED (HTTP 404). '
        'Verify that the exact repository is selected for the fine-grained token.\n\n'
        'GitHub response: ${res.body}',
      );
    }

    if (res.statusCode != 200) {
      throw GithubSyncException(
        'REPOSITORY ACCESS FAILED: ${res.statusCode} ${res.body}',
      );
    }

    final dynamic decoded = jsonDecode(res.body);

    if (decoded is! Map<String, dynamic>) {
      throw GithubSyncException(
        'REPOSITORY ACCESS FAILED: invalid GitHub response.',
      );
    }

    final String defaultBranch =
        (decoded['default_branch'] ?? '').toString().trim();

    if (defaultBranch.isEmpty) {
      throw GithubSyncException(
        'REPOSITORY ACCESS FAILED: GitHub did not provide a default branch.',
      );
    }

    return defaultBranch;
  }

  Future<String?> _getBranchRefSha() async {
    final res = await _send(
      () => _client.get(
        _api('/git/ref/heads/$branch'),
        headers: _headers,
      ),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      return (data['object'] as Map<String, dynamic>)['sha'] as String;
    }

    if (res.statusCode == 404) {
      if (branch == 'main') {
        final String? defaultBranch = await _getRepositoryDefaultBranch();

        if (defaultBranch != null && defaultBranch != branch) {
          _resolvedBranch = defaultBranch;

          final retry = await _send(
            () => _client.get(
              _api('/git/ref/heads/$defaultBranch'),
              headers: _headers,
            ),
          );

          if (retry.statusCode == 200) {
            final retryData = jsonDecode(retry.body) as Map<String, dynamic>;

            return (retryData['object'] as Map<String, dynamic>)['sha']
                as String;
          }

          if (retry.statusCode == 404) {
            return null;
          }

          if (retry.statusCode == 403) {
            throw _permissionDenied(
              retry,
              operation: 'reading the default branch reference',
              documentedPermission: 'contents=read',
              repositoryAccessAlreadyValidated: true,
            );
          }

          throw GithubSyncException(
            'DEFAULT BRANCH REF FETCH FAILED: '
            '${retry.statusCode} ${retry.body}',
          );
        }
        return null;
      }
      return null;
    }

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'reading the Git reference',
        documentedPermission: 'contents=read',
        repositoryAccessAlreadyValidated: _repositoryMetadataValidated,
      );
    }

    throw GithubSyncException(
      'REF FETCH FAILED: ${res.statusCode} ${res.body}',
    );
  }

  Future<void> createFileIfAbsent({
    required String path,
    required String content,
    required String message,
  }) async {
    final String encodedContent = base64Encode(utf8.encode(content));
    final String targetBranch = _resolvedBranch ?? branch;

    final res = await _send(
      () => _client.put(
        _api('/contents/$path'),
        headers: _headers,
        body: jsonEncode({
          'message': message,
          'content': encodedContent,
          'branch': targetBranch,
        }),
      ),
    );

    if (res.statusCode == 201) {
      final dynamic decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['content'] is! Map<String, dynamic> ||
          decoded['commit'] is! Map<String, dynamic>) {
        throw GithubSyncException(
          'GITHUB FILE CREATE SUCCEEDED but GitHub returned an invalid response.',
        );
      }
      return;
    }

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'creating "$path"',
        documentedPermission: 'contents=write',
        repositoryAccessAlreadyValidated: _repositoryMetadataValidated,
      );
    }

    if (res.statusCode == 422) {
      throw GithubFileAlreadyExists(
        'GitHub did not create "$path" because the target file or write parameters already exist/conflict (HTTP 422).\n\n'
        'GitHub response: ${res.body}',
      );
    }

    throw GithubSyncException(
      'GITHUB FILE CREATE FAILED for "$path": HTTP ${res.statusCode}.\n\n'
      'GitHub response: ${res.body}',
    );
  }

  Future<void> _initializeEmptyRepository({
    required String path,
    required String content,
    required String message,
  }) async {
    final String encodedContent = base64Encode(utf8.encode(content));

    final res = await _send(
      () => _client.put(
        _api('/contents/$path'),
        headers: _headers,
        body: jsonEncode({
          'message': message,
          'content': encodedContent,
        }),
      ),
    );

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'initializing the empty repository',
        documentedPermission: 'contents=write',
        repositoryAccessAlreadyValidated: true,
      );
    }

    if (res.statusCode != 201) {
      throw GithubSyncException(
        'EMPTY REPOSITORY INITIALIZATION FAILED: '
        '${res.statusCode} ${res.body}',
      );
    }

    final dynamic decoded = jsonDecode(res.body);

    if (decoded is! Map<String, dynamic>) {
      throw GithubSyncException(
        'EMPTY REPOSITORY INITIALIZATION FAILED: '
        'invalid GitHub response.',
      );
    }

    final dynamic contentResult = decoded['content'];
    final dynamic commitResult = decoded['commit'];

    if (contentResult is! Map<String, dynamic> ||
        commitResult is! Map<String, dynamic>) {
      throw GithubSyncException(
        'EMPTY REPOSITORY INITIALIZATION FAILED: '
        'GitHub did not return a created file and commit.',
      );
    }
  }

  Future<String?> _getCommitTreeSha(String commitSha) async {
    final res = await _send(
      () => _client.get(
        _api('/git/commits/$commitSha'),
        headers: _headers,
      ),
    );

    if (res.statusCode == 401) {
      throw GithubSyncException(
        'GITHUB TOKEN REJECTED while reading the commit tree (HTTP 401). GitHub response: ${res.body}',
      );
    }

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'reading the commit tree',
        documentedPermission: 'contents=read',
        repositoryAccessAlreadyValidated: _repositoryMetadataValidated,
      );
    }

    if (res.statusCode != 200) {
      throw GithubSyncException(
        'COMMIT FETCH FAILED: ${res.statusCode} ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;

    return (data['tree'] as Map<String, dynamic>)['sha'] as String;
  }

  Future<String> _createTree({
    required List<Map<String, dynamic>> entries,
    String? baseTreeSha,
  }) async {
    final Map<String, dynamic> body = {
      'tree': entries,
    };

    if (baseTreeSha != null) {
      body['base_tree'] = baseTreeSha;
    }

    final res = await _send(
      () => _client.post(
        _api('/git/trees'),
        headers: _headers,
        body: jsonEncode(body),
      ),
    );

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'creating a Git tree',
        documentedPermission: 'contents=write',
        repositoryAccessAlreadyValidated: true,
      );
    }

    if (res.statusCode != 201) {
      final String entrySummary = entries
          .map(
            (e) => '${e['path']}:${e['sha'] == null ? 'DELETE' : 'UPSERT'}',
          )
          .join(', ');

      throw GithubSyncException(
        'TREE CREATE FAILED: '
        '${res.statusCode} ${res.body} '
        '| base_tree=$baseTreeSha '
        '| entries=[$entrySummary]',
      );
    }

    return (jsonDecode(res.body) as Map<String, dynamic>)['sha'] as String;
  }

  Future<String> _createRootCommit({
    required String treeSha,
    required String message,
  }) async {
    final res = await _send(
      () => _client.post(
        _api('/git/commits'),
        headers: _headers,
        body: jsonEncode({
          'message': message,
          'tree': treeSha,
          'parents': <String>[],
        }),
      ),
    );

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'creating a commit',
        documentedPermission: 'contents=write',
        repositoryAccessAlreadyValidated: true,
      );
    }

    if (res.statusCode != 201) {
      throw GithubSyncException(
        'COMMIT CREATE FAILED: ${res.statusCode} ${res.body}',
      );
    }

    return (jsonDecode(res.body) as Map<String, dynamic>)['sha'] as String;
  }

  Future<void> _forcePushRef(
    String commitSha, {
    required bool refExists,
  }) async {
    final String targetBranch = _resolvedBranch ?? branch;

    if (refExists) {
      final res = await _send(
        () => _client.patch(
          _api('/git/refs/heads/$targetBranch'),
          headers: _headers,
          body: jsonEncode({
            'sha': commitSha,
            'force': true,
          }),
        ),
      );

      if (res.statusCode == 403) {
        throw _permissionDenied(
          res,
          operation: 'updating the Git branch reference',
          documentedPermission: 'contents=write',
          repositoryAccessAlreadyValidated: true,
        );
      }

      if (res.statusCode != 200) {
        throw GithubSyncException(
          'REF UPDATE FAILED: ${res.statusCode} ${res.body}',
        );
      }
    } else {
      final res = await _send(
        () => _client.post(
          _api('/git/refs'),
          headers: _headers,
          body: jsonEncode({
            'ref': 'refs/heads/$targetBranch',
            'sha': commitSha,
          }),
        ),
      );

      if (res.statusCode == 403) {
        throw _permissionDenied(
          res,
          operation: 'creating the Git branch reference',
          documentedPermission: 'contents=write',
          repositoryAccessAlreadyValidated: true,
        );
      }

      if (res.statusCode != 201) {
        throw GithubSyncException(
          'REF CREATE FAILED: ${res.statusCode} ${res.body}',
        );
      }
    }
  }

  Future<void> amendSync({
    Map<String, String> upsertFiles = const {},
    List<String> deleteFiles = const [],
    Map<String, String> renameFiles = const {},
    String message = 'rocen sync',
  }) async {
    if (upsertFiles.isEmpty && deleteFiles.isEmpty && renameFiles.isEmpty) {
      return;
    }

    final String? currentRefSha = await _getBranchRefSha();
    if (currentRefSha == null) {
      if (upsertFiles.length != 1 ||
          deleteFiles.isNotEmpty ||
          renameFiles.isNotEmpty) {
        throw GithubSyncException(
          'EMPTY REPOSITORY REQUIRES EXACTLY ONE INITIAL FILE.',
        );
      }

      final MapEntry<String, String> initialEntry = upsertFiles.entries.first;

      await _initializeEmptyRepository(
        path: initialEntry.key,
        content: initialEntry.value,
        message: message,
      );

      return;
    }

    final String? baseTreeSha = await _getCommitTreeSha(currentRefSha);

    final Set<String> existingFiles =
        (deleteFiles.isNotEmpty || renameFiles.isNotEmpty)
            ? (await listNoteFiles()).toSet()
            : <String>{};

    final List<String> validDeleteFiles =
        deleteFiles.where(existingFiles.contains).toList();

    final Map<String, String> validRenameFiles = Map.fromEntries(
      renameFiles.entries.where(
        (entry) => existingFiles.contains(entry.key),
      ),
    );

    final List<Map<String, dynamic>> entries = [];

    for (final path in validDeleteFiles) {
      entries.add({
        'path': path,
        'mode': '100644',
        'type': 'blob',
        'sha': null,
      });
    }

    validRenameFiles.forEach((oldPath, newPath) {
      entries.add({
        'path': oldPath,
        'mode': '100644',
        'type': 'blob',
        'sha': null,
      });

      if (!upsertFiles.containsKey(newPath)) {
        entries.add({
          'path': newPath,
          'mode': '100644',
          'type': 'blob',
          'content': upsertFiles[newPath] ?? '',
        });
      }
    });

    upsertFiles.forEach((path, content) {
      entries.add({
        'path': path,
        'mode': '100644',
        'type': 'blob',
        'content': content,
      });
    });

    if (entries.isEmpty) {
      return;
    }

    final String newTreeSha = await _createTree(
      entries: entries,
      baseTreeSha: baseTreeSha,
    );

    final String newCommitSha = await _createRootCommit(
      treeSha: newTreeSha,
      message: message,
    );

    await _forcePushRef(
      newCommitSha,
      refExists: currentRefSha != null,
    );
  }

  Future<({Map<String, dynamic>? content, String? refSha})>
      fetchNoteFileWithRefSha(String fileName) async {
    final String? refSha = await _getBranchRefSha();

    final Map<String, dynamic>? content = await fetchNoteFile(fileName);

    return (
      content: content,
      refSha: refSha,
    );
  }

  Future<Map<String, dynamic>?> fetchNoteFile(
    String fileName,
  ) async {
    final res = await _send(
      () => _client.get(
        _api('/contents/$fileName'),
        headers: _headers,
      ),
    );

    if (res.statusCode == 404) {
      return null;
    }

    if (res.statusCode == 409) {
      final String bodyLower = res.body.toLowerCase();
      if (bodyLower.contains('git repository is empty') ||
          bodyLower.contains('repository is empty')) {
        return null;
      }
    }

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'reading "$fileName"',
        documentedPermission: 'contents=read',
        repositoryAccessAlreadyValidated: _repositoryMetadataValidated,
      );
    }

    if (res.statusCode != 200) {
      throw GithubSyncException(
        'FILE FETCH FAILED: ${res.statusCode} ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;

    final String encodedContent =
        (data['content'] as String).replaceAll('\n', '');

    final String rawJson = utf8.decode(base64.decode(encodedContent));

    return jsonDecode(rawJson) as Map<String, dynamic>;
  }

  Future<void> updateFileWithFastForwardCheck({
    required String path,
    required String content,
    required String message,
    required String? expectedParentSha,
  }) async {
    final String? currentRefSha = await _getBranchRefSha();
    if (currentRefSha != expectedParentSha) {
      throw GithubConditionalWriteConflict(
        'branch moved: '
        'expected parent $expectedParentSha, '
        'actual $currentRefSha',
      );
    }

    final String? baseTreeSha =
        currentRefSha != null ? await _getCommitTreeSha(currentRefSha) : null;

    final String newTreeSha = await _createTree(
      entries: [
        {
          'path': path,
          'mode': '100644',
          'type': 'blob',
          'content': content,
        },
      ],
      baseTreeSha: baseTreeSha,
    );

    final Map<String, dynamic> commitBody = {
      'message': message,
      'tree': newTreeSha,
      'parents': currentRefSha != null ? [currentRefSha] : <String>[],
    };

    final commitRes = await _send(
      () => _client.post(
        _api('/git/commits'),
        headers: _headers,
        body: jsonEncode(commitBody),
      ),
    );

    if (commitRes.statusCode == 403) {
      throw _permissionDenied(
        commitRes,
        operation: 'creating the conditional commit',
        documentedPermission: 'contents=write',
        repositoryAccessAlreadyValidated: true,
      );
    }

    if (commitRes.statusCode != 201) {
      throw GithubSyncException(
        'CONDITIONAL COMMIT CREATE FAILED: '
        '${commitRes.statusCode} ${commitRes.body}',
      );
    }

    final String newCommitSha =
        (jsonDecode(commitRes.body) as Map<String, dynamic>)['sha'] as String;

    if (currentRefSha == null) {
      final createRes = await _send(
        () => _client.post(
          _api('/git/refs'),
          headers: _headers,
          body: jsonEncode({
            'ref': 'refs/heads/$branch',
            'sha': newCommitSha,
          }),
        ),
      );

      if (createRes.statusCode == 422) {
        throw GithubConditionalWriteConflict(
          'branch was created by another writer before '
          'this ref-create landed',
        );
      }

      if (createRes.statusCode == 403) {
        throw _permissionDenied(
          createRes,
          operation: 'creating the conditional branch reference',
          documentedPermission: 'contents=write',
          repositoryAccessAlreadyValidated: true,
        );
      }

      if (createRes.statusCode != 201) {
        throw GithubSyncException(
          'CONDITIONAL REF CREATE FAILED: '
          '${createRes.statusCode} ${createRes.body}',
        );
      }

      return;
    }

    final String targetBranch = _resolvedBranch ?? branch;

    final updateRes = await _send(
      () => _client.patch(
        _api('/git/refs/heads/$targetBranch'),
        headers: _headers,
        body: jsonEncode({
          'sha': newCommitSha,
          'force': false,
        }),
      ),
    );

    if (updateRes.statusCode == 422 || updateRes.statusCode == 409) {
      throw GithubConditionalWriteConflict(
        'REF UPDATE REJECTED '
        '(not a fast-forward - branch moved): '
        '${updateRes.statusCode} ${updateRes.body}',
      );
    }

    if (updateRes.statusCode == 403) {
      throw _permissionDenied(
        updateRes,
        operation: 'updating the conditional branch reference',
        documentedPermission: 'contents=write',
        repositoryAccessAlreadyValidated: true,
      );
    }

    if (updateRes.statusCode != 200) {
      throw GithubSyncException(
        'CONDITIONAL REF UPDATE FAILED: '
        '${updateRes.statusCode} ${updateRes.body}',
      );
    }
  }

  Future<List<String>> listNoteFiles() async {
    final res = await _send(
      () => _client.get(
        _api('/contents'),
        headers: _headers,
      ),
    );

    debugPrint(
      'LIST NOTE FILES: status=${res.statusCode}',
    );

    if (res.statusCode == 404) {
      return [];
    }

    if (res.statusCode == 403) {
      throw _permissionDenied(
        res,
        operation: 'listing repository contents',
        documentedPermission: 'contents=read',
        repositoryAccessAlreadyValidated: _repositoryMetadataValidated,
      );
    }

    if (res.statusCode != 200) {
      throw GithubSyncException(
        'DIRECTORY LIST FAILED: '
        '${res.statusCode} ${res.body}',
      );
    }

    final dynamic decoded = jsonDecode(res.body);

    if (decoded is! List) {
      debugPrint(
        'LIST NOTE FILES: response was not a List, '
        'raw body: ${res.body}',
      );

      return [];
    }

    final List<String> names = decoded
        .where(
          (e) => e['type'] == 'file' && (e['name'] as String).endsWith('.json'),
        )
        .map((e) => e['name'] as String)
        .toList();

    debugPrint(
      'LIST NOTE FILES: found ${decoded.length} '
      'entries total, ${names.length} .json files: $names',
    );

    return names;
  }
}
