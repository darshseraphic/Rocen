import 'package:flutter_test/flutter_test.dart';
import 'package:rocen/core/strict_json.dart';

void main() {
  test('accepts exact maximum UTF-8 size and rejects one byte over', () {
    final String exact = '{}${' ' * (maxAuthorityJsonBytes - 2)}';
    expect(exact.codeUnits.length, maxAuthorityJsonBytes);
    expect(() => requireNoDuplicateJsonProperties(exact), returnsNormally);
    expect(
      () => requireNoDuplicateJsonProperties('$exact '),
      throwsA(isA<InvalidAuthorityDocumentException>()),
    );
    final String multibyte = '"${List<String>.filled(65535, '😀').join()}  "';
    expect(multibyte.length, lessThan(maxAuthorityJsonBytes));
    expect(() => requireNoDuplicateJsonProperties(multibyte), returnsNormally);
    expect(
      () => requireNoDuplicateJsonProperties(
          '"${List<String>.filled(65536, '😀').join()}"'),
      throwsA(isA<InvalidAuthorityDocumentException>()),
    );
  });

  test('accepts exact nesting limit and rejects one deeper', () {
    final String exact =
        '${'[' * maxAuthorityJsonDepth}0${']' * maxAuthorityJsonDepth}';
    expect(() => requireNoDuplicateJsonProperties(exact), returnsNormally);
    final String tooDeep =
        '${'[' * (maxAuthorityJsonDepth + 1)}0${']' * (maxAuthorityJsonDepth + 1)}';
    expect(
      () => requireNoDuplicateJsonProperties(tooDeep),
      throwsA(isA<InvalidAuthorityDocumentException>()),
    );
  });

  test('rejects oversized arrays and deeply nested mixed containers safely',
      () {
    final String tooManyEntries =
        '[${List<String>.filled(maxAuthorityArrayEntries + 1, '0').join(',')}]';
    expect(
      () => requireNoDuplicateJsonProperties(tooManyEntries),
      throwsA(isA<InvalidAuthorityDocumentException>()),
    );
    const int depth = maxAuthorityJsonDepth + 1;
    final String deep =
        '${List<String>.filled(depth, '[{"x":').join()}0${List<String>.filled(depth, '}]').join()}';
    expect(
      () => requireNoDuplicateJsonProperties(deep),
      throwsA(isA<InvalidAuthorityDocumentException>()),
    );
  });

  test('escaped duplicate aliases remain rejected', () {
    expect(
      () =>
          requireNoDuplicateJsonProperties('{"deviceId":1,"device\\u0049d":2}'),
      throwsA(isA<InvalidAuthorityDocumentException>()),
    );
  });
}
