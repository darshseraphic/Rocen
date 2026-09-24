import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/database.dart';
import 'package:Rocen/features/bookmarks.dart';

void main() {
  test('protected persistence is explicitly unavailable during cutover', () {
    expect(protectedApplicationPersistenceAvailable, isFalse);
    expect(TodoNotifier.protectedDataUnavailableMessage, contains('DISABLED'));
  });

  test('capture writes fail closed without persistence side effects', () async {
    final database = DatabaseNotifier();
    expect(await database.insertItem('secret', 'note'), isFalse);
    expect(await database.updateItem('id', 'secret'), isFalse);
    expect(await database.insertMultipleItems(['/secret/path'], 'imported_clip'), isFalse);
    expect(await database.deleteItem('id'), isFalse);
    expect(await database.importFromSchemaJson('{"content":"secret"}'), isFalse);
    expect(database.exportToSchemaJson(), '[]');
  });

  test('todo protected-data operations fail closed', () async {
    final todos = TodoNotifier();
    expect(await todos.addTask('secret todo'), isFalse);
    expect(await todos.toggleTask('id'), isFalse);
    expect(await todos.deleteTask('id'), isFalse);
  });
}
