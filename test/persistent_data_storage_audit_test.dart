import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory root = Directory.current;
  final Directory sourceRoot = Directory('${root.path}/lib');

  String readSource(String relativePath) =>
      File('${sourceRoot.path}/$relativePath').readAsStringSync();

  test('production persistence is limited to explicit non-sensitive metadata or blocked protected stores', () {
    final List<File> productionFiles = sourceRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);

    final Set<String> allowedHiveBoxNames = <String>{
      'rocen_settings_box',
      // The clean-cutover reset is intentionally allowed to name these only so
      // disposable legacy data can be destroyed before normal operation.
      'rocen_captures_box',
      'rocen_todos_box',
    };

    for (final File file in productionFiles) {
      final String text = file.readAsStringSync();
      for (final match in RegExp(
        r'''(?:Hive\.(?:box|openBox|deleteBoxFromDisk)|static const String _boxName\s*=)\s*\(?\s*['"]([^'"]+)['"]''',
      ).allMatches(text)) {
        final String boxName = match.group(1)!;
        expect(
          allowedHiveBoxNames,
          contains(boxName),
          reason: 'Unexpected persistent Hive box in ${file.path}: $boxName',
        );
      }
    }

    expect(readSource('core/database.dart'), isNot(contains('hive_flutter')));
    expect(readSource('features/bookmarks.dart'), isNot(contains('hive_flutter')));
    expect(
      readSource('core/database.dart'),
      contains('protectedApplicationPersistenceAvailable = false'),
    );
  });

  test('sensitive values are not written to production persistent stores', () {
    final List<RegExp> sensitivePersistencePatterns = <RegExp>[
      RegExp(
        r'''(?s)(?:Hive\.box\([^;]*?\)|settingsBox|box)\s*\.\s*(?:put|add|putAll)\s*\([^;]*,\s*[^;]*(?:\btoken\b|\baccessToken\b|\bgithub[_-]?token\b)[^;]*;''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?s)(?:Hive\.box\([^;]*?\)|settingsBox|box)\s*\.\s*(?:put|add|putAll)\s*\([^;]*,\s*[^;]*(?:\bnote\.content\b|\bnoteContent\b|\bCaptureItem\b|\bnoteBody\b)[^;]*;''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?s)(?:Hive\.box\([^;]*?\)|settingsBox|box)\s*\.\s*(?:put|add|putAll)\s*\([^;]*,\s*[^;]*(?:\bTodoItem\b|\btodos?\b|\btodoText\b)[^;]*;''',
        caseSensitive: false,
      ),
    ];

    for (final File file in productionFiles) {
      final String source = file.readAsStringSync();
      for (final RegExp pattern in sensitivePersistencePatterns) {
        expect(
          pattern.hasMatch(source),
          isFalse,
          reason:
              'Sensitive application data appears to be written to persistent storage in ${file.path}: ${pattern.pattern}',
        );
      }
    }
  });
}
