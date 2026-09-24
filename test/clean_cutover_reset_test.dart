import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Rocen/core/clean_cutover_reset.dart';
import 'package:Rocen/core/master_key_local_store.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_cutover_reset_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box(MasterKeyLocalStore.boxName).delete('block_b_clean_cutover_completed_v1');
    for (final boxName in <String>['rocen_captures_box', 'rocen_todos_box']) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).clear();
        await Hive.box(boxName).close();
      }
      await Hive.deleteBoxFromDisk(boxName);
    }
  });

  test('purge failure returns false and does not report successful reset', () async {
    final result = await CleanCutoverReset.run(
      deleteBox: (boxName) async => throw FileSystemException('simulated purge failure', boxName),
    );
    expect(result, isFalse);
  });

  test('successful purge removes obsolete capture and todo boxes', () async {
    final captures = await Hive.openBox('rocen_captures_box');
    await captures.put('items', <Map<String, dynamic>>[
      {'content': 'disposable test data'},
    ]);
    await captures.close();
    final todos = await Hive.openBox('rocen_todos_box');
    await todos.put('tasks', <Map<String, dynamic>>[
      {'text': 'disposable todo'},
    ]);
    await todos.close();

    final result = await CleanCutoverReset.run();
    expect(result, isTrue);
    expect(Hive.isBoxOpen('rocen_captures_box'), isFalse);
    expect(Hive.isBoxOpen('rocen_todos_box'), isFalse);
    final reopenedCapture = await Hive.openBox('rocen_captures_box');
    final reopenedTodos = await Hive.openBox('rocen_todos_box');
    expect(reopenedCapture.isEmpty, isTrue);
    expect(reopenedTodos.isEmpty, isTrue);
    expect(
      Hive.box(MasterKeyLocalStore.boxName)
          .get('block_b_clean_cutover_completed_v1'),
      isTrue,
    );
    await reopenedCapture.close();
    await reopenedTodos.close();
  });
}
