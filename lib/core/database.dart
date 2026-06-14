import 'dart:convert'; // Added for seamless high-performance JSON conversion
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class CaptureItem {
  final String id;
  final String title;
  final String content;
  final String type;
  final DateTime timestamp;

  CaptureItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory CaptureItem.fromMap(Map<String, dynamic> map) {
    return CaptureItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      type: map['type'] ?? '',
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}

class DatabaseNotifier extends Notifier<List<CaptureItem>> {
  static const String _boxName = 'rocen_captures_box';

  @override
  List<CaptureItem> build() {
    _initAndLoad();
    return [];
  }

  Future<void> _initAndLoad() async {
    final box = await Hive.openBox(_boxName);
    final List<dynamic>? storedRaw = box.get('items');

    if (storedRaw != null && storedRaw.isNotEmpty) {
      state = storedRaw
          .map((item) => CaptureItem.fromMap(Map<String, dynamic>.from(item)))
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
  }

  /// Converts the current app state into a raw JSON string for external file export
  String exportToSchemaJson() {
    final List<Map<String, dynamic>> rawList = state.map((item) => item.toMap()).toList();
    return jsonEncode(rawList);
  }

  /// Validates structural composition, overwrites local storage, and updates the reactive UI
  Future<bool> importFromSchemaJson(String jsonRawString) async {
    try {
      final decoded = jsonDecode(jsonRawString);
      if (decoded is! List) return false;

      final List<CaptureItem> importedItems = [];
      for (final item in decoded) {
        if (item is Map) {
          final convertedMap = Map<String, dynamic>.from(item);
          // High safety verification constraint mapping
          if (convertedMap.containsKey('id') &&
              convertedMap.containsKey('content') &&
              convertedMap.containsKey('type')) {
            importedItems.add(CaptureItem.fromMap(convertedMap));
          }
        }
      }

      // If the file is completely corrupt or unreadable, safely decline execution
      if (importedItems.isEmpty && decoded.isNotEmpty) return false;

      // Overwrite persistent device memory box safely
      final box = await Hive.openBox(_boxName);
      await box.put('items', importedItems.map((e) => e.toMap()).toList());

      // Force instant global Riverpod application state synchronizations
      state = importedItems;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Optimized batch insertion handling high-volume automatic asset additions
  Future<void> insertMultipleItems(List<String> filePaths, String type) async {
    final int baseTimestamp = DateTime.now().microsecondsSinceEpoch;

    final List<CaptureItem> newItems = filePaths.asMap().entries.map((entry) {
      return CaptureItem(
        id: (baseTimestamp + entry.key).toString(),
        title: '',
        content: entry.value,
        type: type,
        timestamp: DateTime.now(),
      );
    }).toList();

    state = [...newItems, ...state];

    final box = await Hive.openBox(_boxName);
    await box.put('items', state.map((e) => e.toMap()).toList());
  }

  /// Inserts a singular capture node directly into Hive and synchronizes state
  Future<void> insertItem(String content, String type, {String title = ''}) async {
    final newItem = CaptureItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: type,
      timestamp: DateTime.now(),
    );

    state = [newItem, ...state];

    final box = await Hive.openBox(_boxName);
    await box.put('items', state.map((e) => e.toMap()).toList());
  }

  /// Updates specific elements within persistent storage via micro-targeted identification matching
  Future<void> updateItem(String id, String newContent, {String? title}) async {
    state = [
      for (final item in state)
        if (item.id == id)
          CaptureItem(
            id: item.id,
            title: title ?? item.title,
            content: newContent,
            type: item.type,
            timestamp: item.timestamp,
          )
        else
          item,
    ];

    final box = await Hive.openBox(_boxName);
    await box.put('items', state.map((e) => e.toMap()).toList());
  }

  /// Deletes explicit objects safely and rewires local collection arrays
  Future<void> deleteItem(String id) async {
    state = state.where((item) => item.id != id).toList();
    final box = await Hive.openBox(_boxName);
    await box.put('items', state.map((e) => e.toMap()).toList());
  }
}

final localDatabaseProvider = NotifierProvider<DatabaseNotifier, List<CaptureItem>>(DatabaseNotifier.new);