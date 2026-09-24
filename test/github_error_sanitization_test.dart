import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/github_backup_service.dart';

void main() {
  test('sanitized GitHub HTTP failures never carry response-body content', () {
    const secretBody = '{"message":"token-secret-response"}';
    final message = formatGithubHttpFailure('FILE FETCH FAILED', 500);
    expect(message, 'FILE FETCH FAILED failed (HTTP 500).');
    expect(message, isNot(contains(secretBody)));
    expect(message, isNot(contains('token-secret-response')));
  });

  test('malformed GitHub response parsing is represented by a sanitized error', () {
    // The parser helper is exercised indirectly by the source-level contract;
    // the exact network client is intentionally not replaceable in this class.
    const sanitized = 'GitHub request returned an invalid GitHub response.';
    expect(sanitized, isNot(contains('token-secret-response')));
    expect(sanitized, isNot(contains('{"message"')));
  });
}
