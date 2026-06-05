import 'package:flutter_riverpod/legacy.dart';

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
    // Initial minimalist mock data to prevent an empty screen experience on first launch
    state = [
      CaptureItem(
        id: '1',
        title: 'WELCOME',
        content: 'Rocen minimal capture engine active.',
        type: 'idea',
        timestamp: DateTime.now(),
      ),
    ];
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

    // Update the UI state explicitly without persistent storage hooks
    state = [newItem, ...state];
  }

  Future<void> deleteItem(String id) async {
    state = state.where((item) => item.id != id).toList();
  }
}

final localDatabaseProvider =
StateNotifierProvider<DatabaseNotifier, List<CaptureItem>>((ref) {
  return DatabaseNotifier();
});