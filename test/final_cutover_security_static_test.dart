import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;
  final sourceRoot = Directory('${root.path}/lib');

  String source(String relativePath) =>
      File('${sourceRoot.path}/$relativePath').readAsStringSync();

  test('protected persistence is fail-closed and legacy APIs remain absent', () {
    final database = source('core/database.dart');
    final quickNote = source('features/quicknote.dart');
    final ideaInbox = source('features/ideainbox.dart');
    final bookmarks = source('features/bookmarks.dart');
    final clipboard = source('features/clipboard.dart');

    expect(database, contains('protectedApplicationPersistenceAvailable = false'));
    expect(database, isNot(contains('box.put(\'items\'')));
    expect(database, isNot(contains('toMap()')));
    expect(database, isNot(contains('fromMap(')));

    expect(quickNote, contains('if (!protectedApplicationPersistenceAvailable) return;'));
    expect(ideaInbox, contains('NOT SAVED: PROTECTED PERSISTENCE IS UNAVAILABLE.'));
    expect(bookmarks, contains('if (!protectedApplicationPersistenceAvailable) return;'));
    expect(clipboard, contains('MEDIA NOT SAVED'));

    for (final path in <String>[
      'core/database.dart',
      'features/quicknote.dart',
      'features/ideainbox.dart',
      'features/bookmarks.dart',
      'features/settings.dart',
    ]) {
      final text = source(path);
      expect(text, isNot(contains('system_crypto_pin')));
    }
  });
}
