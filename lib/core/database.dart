import 'package:flutter_riverpod/legacy.dart';
import 'storage_service.dart';

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

class DatabaseNotifier extends StateNotifier<List<CaptureItem>> {
  DatabaseNotifier() : super([]) {
    loadItems();
  }

  void loadItems() {
    final data = StorageService.box.values
        .map(
          (e) => CaptureItem.fromMap(
        Map<String, dynamic>.from(e as Map),
      ),
    )
        .toList();

    data.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    state = data;
  }

  Future<void> insertItem(
      String content,
      String type, {
        String title = '',
      }) async {
    final newItem = CaptureItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: type,
      timestamp: DateTime.now(),
    );

    await StorageService.box.put(
      newItem.id,
      newItem.toMap(),
    );

    state = [newItem, ...state];
  }

  Future<void> deleteItem(String id) async {
    await StorageService.box.delete(id);

    state = state.where((item) => item.id != id).toList();
  }

  Future<void> clearAll() async {
    await StorageService.box.clear();
    state = [];
  }
}

final localDatabaseProvider =
StateNotifierProvider<DatabaseNotifier, List<CaptureItem>>(
      (ref) => DatabaseNotifier(),
);