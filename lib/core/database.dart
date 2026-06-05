import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

class CaptureItem {
  final String id;
  final String title;    // Added Title Field
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
}

class DatabaseNotifier extends StateNotifier<List<CaptureItem>> {
  DatabaseNotifier() : super([]);

  void insertItem(String content, String type, {String title = ''}) {
    final newItem = CaptureItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: type,
      timestamp: DateTime.now(),
    );
    state = [newItem, ...state];
  }

  void deleteItem(String id) {
    state = state.where((item) => item.id != id).toList();
  }
}

final localDatabaseProvider = StateNotifierProvider<DatabaseNotifier, List<CaptureItem>>((ref) {
  return DatabaseNotifier();
});