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

String formatGithubHttpFailure(String operation, int statusCode) =>
    '$operation failed (HTTP $statusCode).';

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
    } on Object {
      // Do not propagate socket/timeout/native error text: it may contain
      // implementation details or request-specific data.
      throw GithubSyncException(
        'SECURE CONNECTION FAILED while contacting GitHub.',
      );
    }
  }


  dynamic _decodeResponseJson(http.Response response, String operation) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw GithubSyncException('$operation returned an invalid GitHub response.');
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
      '$permissionText Check the token repository selection and repository permissions. '
      '${formatGithubHttpFailure('GITHUB TOKEN PERMISSION DENIED while $operation', res.statusCode)}',
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
        'The token may be invalid, expired, revoked, or otherwise rejected by GitHub. '
        '${formatGithubHttpFailure('GitHub request', res.statusCode)}',
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
        'Verify that the exact repository is selected for the fine-grained token. '
        '${formatGithubHttpFailure('GitHub request', res.statusCode)}',
      );
    }

    if (res.statusCode != 200) {
      throw GithubSyncException(
        formatGithubHttpFailure('REPOSITORY ACCESS FAILED for "$repoPath"', res.statusCode),
      );
    }

    final dynamic decoded = _decodeResponseJson(res, 'GitHub request');
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
        'permission. Rocen backup requires repository Contents write access.',
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
        'The token may be invalid, expired, revoked, or otherwise rejected by GitHub. '
        '${formatGithubHttpFailure('GitHub request', res.statusCode)}',
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
        'Verify that the exact repository is selected for the fine-grained token. '
        '${formatGithubHttpFailure('GitHub request', res.statusCode)}',
      );
    }

    if (res.statusCode != 200) {
      throw GithubSyncException(
        formatGithubHttpFailure('REPOSITORY ACCESS FAILED', res.statusCode),
      );
    }

    final dynamic decoded = _decodeResponseJson(res, 'GitHub request');

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
      final data = _decodeResponseJson(res, 'GitHub request') as Map<String, dynamic>;

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
            final retryData = _decodeResponseJson(retry, 'GitHub branch request') as Map<String, dynamic>;

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
            formatGithubHttpFailure('DEFAULT BRANCH REF FETCH FAILED', retry.statusCode),
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
      formatGithubHttpFailure('REF FETCH FAILED', res.statusCode),
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
      final dynamic decoded = _decodeResponseJson(res, 'GitHub request');
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
        'GitHub did not create "$path" because the target file or write parameters already exist/conflict (HTTP 422).',
      );
    }

    throw GithubSyncException(
      formatGithubHttpFailure('GITHUB FILE CREATE FAILED for "$path"', res.statusCode),
    );
  }

  Future<String> _getCommitTreeSha(String commitSha) async {
    final res = await _send(
      () => _client.get(
        _api('/git/commits/$commitSha'),
        headers: _headers,
      ),
    );

    if (res.statusCode == 401) {
      throw GithubSyncException(
        'GITHUB TOKEN REJECTED while reading the commit tree (HTTP 401).',
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
        formatGithubHttpFailure('COMMIT FETCH FAILED', res.statusCode),
      );
    }

    final dynamic decoded = _decodeResponseJson(res, 'GitHub request');
    if (decoded is! Map<String, dynamic>) {
      throw GithubSyncException(
        'GitHub request returned an invalid GitHub response.',
      );
    }

    final dynamic tree = decoded['tree'];
    if (tree is! Map<String, dynamic>) {
      throw GithubSyncException(
        'GitHub request returned an invalid GitHub response.',
      );
    }

    final dynamic sha = tree['sha'];
    if (sha is! String ||
        sha.isEmpty ||
        !RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(sha)) {
      throw GithubSyncException(
        'GitHub request returned an invalid GitHub response.',
      );
    }

    return sha;
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
        '${formatGithubHttpFailure('TREE CREATE FAILED', res.statusCode)} '
        'base_tree=$baseTreeSha | entries=[$entrySummary]',
      );
    }

    return (_decodeResponseJson(res, 'GitHub request') as Map<String, dynamic>)['sha'] as String;
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
        formatGithubHttpFailure('FILE FETCH FAILED', res.statusCode),
      );
    }

    final dynamic decoded = _decodeResponseJson(res, 'GitHub file fetch');
    if (decoded is! Map<String, dynamic>) {
      throw GithubSyncException(
        'FILE FETCH FAILED: GitHub returned an invalid file response.',
      );
    }

    try {
      final String encodedContent =
          (decoded['content'] as String).replaceAll('\n', '');
      final String rawJson = utf8.decode(base64.decode(encodedContent));
      final dynamic fileJson = jsonDecode(rawJson);
      if (fileJson is! Map<String, dynamic>) {
        throw const FormatException('file payload is not an object');
      }
      return fileJson;
    } catch (_) {
      throw GithubSyncException(
        'FILE FETCH FAILED: GitHub returned invalid file content.',
      );
    }
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
        formatGithubHttpFailure('CONDITIONAL COMMIT CREATE FAILED', commitRes.statusCode),
      );
    }

    final String newCommitSha =
        (_decodeResponseJson(commitRes, 'GitHub commit request') as Map<String, dynamic>)['sha'] as String;

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
          formatGithubHttpFailure('CONDITIONAL REF CREATE FAILED', createRes.statusCode),
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
        'REF UPDATE REJECTED (not a fast-forward - branch moved): '
        'HTTP ${updateRes.statusCode}.',
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
        formatGithubHttpFailure('CONDITIONAL REF UPDATE FAILED', updateRes.statusCode),
      );
    }
  }

  /// Atomically publishes multiple authority-sensitive files in one
  /// non-force fast-forward commit. The branch SHA is compared immediately
  /// before constructing the commit and GitHub itself rejects a moved ref.
  /// This is intended for recovery/password metadata, never for force-pushed
  /// history rewriting.
  Future<void> updateFilesWithFastForwardCheck({
    required Map<String, String> updates,
    required String message,
    required String? expectedParentSha,
  }) async {
    if (updates.isEmpty) return;

    final String? currentRefSha = await _getBranchRefSha();
    if (currentRefSha != expectedParentSha) {
      throw GithubConditionalWriteConflict(
        'branch moved: expected parent $expectedParentSha, actual $currentRefSha',
      );
    }

    if (currentRefSha == null) {
      throw GithubSyncException(
        'MULTI-FILE CONDITIONAL UPDATE REQUIRES AN INITIALIZED REPOSITORY.',
      );
    }

    final String baseTreeSha = await _getCommitTreeSha(currentRefSha);
    final List<Map<String, dynamic>> entries = updates.entries
        .map((entry) => <String, dynamic>{
              'path': entry.key,
              'mode': '100644',
              'type': 'blob',
              'content': entry.value,
            })
        .toList(growable: false);

    final String newTreeSha = await _createTree(
      entries: entries,
      baseTreeSha: baseTreeSha,
    );
    final http.Response commitRes = await _send(
      () => _client.post(
        _api('/git/commits'),
        headers: _headers,
        body: jsonEncode({
          'message': message,
          'tree': newTreeSha,
          'parents': [currentRefSha],
        }),
      ),
    );

    if (commitRes.statusCode == 403) {
      throw _permissionDenied(
        commitRes,
        operation: 'creating the multi-file conditional commit',
        documentedPermission: 'contents=write',
        repositoryAccessAlreadyValidated: true,
      );
    }
    if (commitRes.statusCode != 201) {
      throw GithubSyncException(
        'MULTI-FILE CONDITIONAL COMMIT FAILED: HTTP ${commitRes.statusCode}',
      );
    }

    final String newCommitSha =
        (_decodeResponseJson(commitRes, 'GitHub commit request') as Map<String, dynamic>)['sha'] as String;
    final String targetBranch = _resolvedBranch ?? branch;
    final http.Response updateRes = await _send(
      () => _client.patch(
        _api('/git/refs/heads/$targetBranch'),
        headers: _headers,
        body: jsonEncode({
          'sha': newCommitSha,
          'force': false,
        }),
      ),
    );

    if (updateRes.statusCode == 409 || updateRes.statusCode == 422) {
      throw GithubConditionalWriteConflict(
        'conditional multi-file ref update rejected because the branch moved',
      );
    }
    if (updateRes.statusCode == 403) {
      throw _permissionDenied(
        updateRes,
        operation: 'updating the multi-file conditional branch reference',
        documentedPermission: 'contents=write',
        repositoryAccessAlreadyValidated: true,
      );
    }
    if (updateRes.statusCode != 200) {
      throw GithubSyncException(
        'MULTI-FILE CONDITIONAL REF UPDATE FAILED: HTTP ${updateRes.statusCode}',
      );
    }
  }

}
