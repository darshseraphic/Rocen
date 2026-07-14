import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class CaptureItem {
  final String id;
  final String title;
  final String content;
  final String type;
  final DateTime timestamp;
  final bool backupEnabled;

  CaptureItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.timestamp,
    this.backupEnabled = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'backupEnabled': backupEnabled,
    };
  }

  factory CaptureItem.fromMap(Map<String, dynamic> map) {
    return CaptureItem(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      timestamp: map['timestamp'] != null
          ? (DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now())
          : DateTime.now(),
      backupEnabled: map['backupEnabled'] == true,
    );
  }
}

class DatabaseNotifier extends Notifier<List<CaptureItem>> {
  static const String _boxName = 'rocen_captures_box';
  static const String _syncQueueKey = 'sync_queue';

  @override
  List<CaptureItem> build() {
    _initAndLoad();
    return [];
  }

  Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return await Hive.openBox(_boxName);
  }

  Future<void> _initAndLoad() async {
    try {
      final box = await _getBox();
      final List<dynamic>? storedRaw = box.get('items');

      if (storedRaw != null && storedRaw.isNotEmpty) {
        state = storedRaw
            .map((item) {
          try {
            if (item is Map) {
              return CaptureItem.fromMap(Map<String, dynamic>.from(item));
            }
            return null;
          } catch (e) {
            debugPrint('System Parsing Exception: Element sequence skip occurred -> $e');
            return null;
          }
        })
            .whereType<CaptureItem>()
            .toList();
      } else {
        final initialItem = CaptureItem(
          id: '1',
          title: 'WELCOME',
          content: 'Rocen minimal capture engine active.',
          type: 'clip',
          timestamp: DateTime.now(),
        );
        state = [initialItem];
        await box.put('items', state.map((e) => e.toMap()).toList());
      }
    } catch (e) {
      debugPrint('Critical Local Storage Pipeline Error on Bootstrap: $e');
      state = [];
    }
  }

  String exportToSchemaJson() {
    try {
      final List<Map<String, dynamic>> rawList = state.map((item) => item.toMap()).toList();
      return jsonEncode(rawList);
    } catch (e) {
      debugPrint('Export Serialization Flaw: Failed to output raw data matrices -> $e');
      return '[]';
    }
  }

  Future<bool> importFromSchemaJson(String jsonRawString) async {
    if (jsonRawString.trim().isEmpty) return false;

    try {
      final decoded = jsonDecode(jsonRawString);
      if (decoded is! List) return false;

      final List<CaptureItem> importedItems = [];
      for (final item in decoded) {
        if (item is Map) {
          final convertedMap = Map<String, dynamic>.from(item);

          if (convertedMap.containsKey('id') &&
              convertedMap.containsKey('content') &&
              convertedMap.containsKey('type')) {
            importedItems.add(CaptureItem.fromMap(convertedMap));
          }
        }
      }

      if (importedItems.isEmpty && decoded.isNotEmpty) return false;

      final box = await _getBox();
      await box.put('items', importedItems.map((e) => e.toMap()).toList());

      state = importedItems;
      return true;
    } catch (e) {
      debugPrint('Import Handshake Exception: Transaction declined due to format anomaly -> $e');
      return false;
    }
  }

  Future<void> insertMultipleItems(List<String> filePaths, String type) async {
    if (filePaths.isEmpty) return;

    final int baseTimestamp = DateTime.now().microsecondsSinceEpoch;
    final DateTime operationTime = DateTime.now();

    final List<CaptureItem> newItems = filePaths.asMap().entries.map((entry) {
      return CaptureItem(
        id: (baseTimestamp + entry.key).toString(),
        title: '',
        content: entry.value,
        type: type,
        timestamp: operationTime,
      );
    }).toList();

    state = [...newItems, ...state];

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
  }

  static String noteFileName(String title) {
    final cleaned = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '$cleaned.json';
  }

  bool titleExists(String title, {String? excludingId}) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    return state.any((item) =>
    item.id != excludingId && item.title.trim().toLowerCase() == normalized);
  }

  Future<Map<String, dynamic>> _readSyncQueue(Box box) async {
    final raw = box.get(_syncQueueKey);
    if (raw == null) {
      return {'deleted': <String>[], 'renamed': <String, String>{}};
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      'deleted': List<String>.from(decoded['deleted'] ?? []),
      'renamed': Map<String, String>.from(decoded['renamed'] ?? {}),
    };
  }

  Future<Map<String, dynamic>> getSyncQueue() async {
    final box = await _getBox();
    return _readSyncQueue(box);
  }

  Future<void> clearSyncQueue() async {
    final box = await _getBox();
    await box.put(_syncQueueKey, jsonEncode({'deleted': <String>[], 'renamed': <String, String>{}}));
  }

  Future<void> _queueRemoteDeletion(String fileName) async {
    final box = await _getBox();
    final queue = await _readSyncQueue(box);
    final List<String> deleted = queue['deleted'];
    final Map<String, String> renamed = queue['renamed'];

    renamed.remove(fileName);
    if (!deleted.contains(fileName)) deleted.add(fileName);

    await box.put(_syncQueueKey, jsonEncode({'deleted': deleted, 'renamed': renamed}));
  }

  Future<void> _queueRemoteRename(String oldFileName, String newFileName) async {
    final box = await _getBox();
    final queue = await _readSyncQueue(box);
    final List<String> deleted = queue['deleted'];
    final Map<String, String> renamed = queue['renamed'];

    deleted.remove(oldFileName);
    renamed[oldFileName] = newFileName;

    await box.put(_syncQueueKey, jsonEncode({'deleted': deleted, 'renamed': renamed}));
  }

  Future<bool> insertItem(String content, String type, {String title = '', bool backupEnabled = false}) async {
    if (backupEnabled && title.trim().isEmpty) return false;
    if (backupEnabled && titleExists(title)) return false;

    final newItem = CaptureItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: type,
      timestamp: DateTime.now(),
      backupEnabled: backupEnabled,
    );

    state = [newItem, ...state];

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
    return true;
  }

  Future<bool> updateItem(String id, String newContent, {String? title, bool? backupEnabled}) async {
    CaptureItem? previous;
    for (final item in state) {
      if (item.id == id) {
        previous = item;
        break;
      }
    }
    if (previous == null) return false;

    final String resolvedTitle = title ?? previous.title;
    final bool resolvedBackup = backupEnabled ?? previous.backupEnabled;

    if (resolvedBackup && resolvedTitle.trim().isEmpty) return false;
    if (resolvedBackup && titleExists(resolvedTitle, excludingId: id)) return false;

    bool stateMutationOccurred = false;

    final List<CaptureItem> updatedCollection = state.map((item) {
      if (item.id == id) {
        stateMutationOccurred = true;
        return CaptureItem(
          id: item.id,
          title: resolvedTitle,
          content: newContent,
          type: item.type,
          timestamp: item.timestamp,
          backupEnabled: resolvedBackup,
        );
      }
      return item;
    }).toList();

    if (!stateMutationOccurred) return false;

    if (previous.backupEnabled && !resolvedBackup) {
      await _queueRemoteDeletion(noteFileName(previous.title));
    } else if (previous.backupEnabled &&
        resolvedBackup &&
        previous.title.trim() != resolvedTitle.trim()) {
      await _queueRemoteRename(noteFileName(previous.title), noteFileName(resolvedTitle));
    }

    state = updatedCollection;

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
    return true;
  }

  Future<void> deleteItem(String id) async {
    CaptureItem? target;
    for (final item in state) {
      if (item.id == id) {
        target = item;
        break;
      }
    }
    if (target == null) return;

    final List<CaptureItem> remainingItems = state.where((item) => item.id != id).toList();
    state = remainingItems;

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());

    if (target.backupEnabled) {
      await _queueRemoteDeletion(noteFileName(target.title));
    }
  }
}

final localDatabaseProvider = NotifierProvider<DatabaseNotifier, List<CaptureItem>>(DatabaseNotifier.new);