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

  CaptureItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.timestamp,
  });

  /// Serializes the core item instance into an explicit structural schema map format
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// High-resilience instantiation factory enforcing structural fallbacks for incoming fields
  factory CaptureItem.fromMap(Map<String, dynamic> map) {
    return CaptureItem(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      timestamp: map['timestamp'] != null
          ? (DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

class DatabaseNotifier extends Notifier<List<CaptureItem>> {
  static const String _boxName = 'rocen_captures_box';

  @override
  List<CaptureItem> build() {
    // Dispatch asynchronous cold boot sequence safely into post-initialization queue
    _initAndLoad();
    return [];
  }

  /// Optimizes instance lookups by retrieving an active box reference or executing open operations
  Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return await Hive.openBox(_boxName);
  }

  /// Handles systemic boot routines, opening local device memory tables and streaming blocks safely
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
        // Initialize structural standard zero-state anchor vector
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

  /// Converts the active system state configuration block into a condensed schema JSON payload string
  String exportToSchemaJson() {
    try {
      final List<Map<String, dynamic>> rawList = state.map((item) => item.toMap()).toList();
      return jsonEncode(rawList);
    } catch (e) {
      debugPrint('Export Serialization Flaw: Failed to output raw data matrices -> $e');
      return '[]';
    }
  }

  /// Validates deep structure parsing bounds, blocks corrupt mutations, and synchronizes memory boxes
  Future<bool> importFromSchemaJson(String jsonRawString) async {
    if (jsonRawString.trim().isEmpty) return false;

    try {
      final decoded = jsonDecode(jsonRawString);
      if (decoded is! List) return false;

      final List<CaptureItem> importedItems = [];
      for (final item in decoded) {
        if (item is Map) {
          final convertedMap = Map<String, dynamic>.from(item);

          // Tight structural gatekeeping validation constraint verification matrix
          if (convertedMap.containsKey('id') &&
              convertedMap.containsKey('content') &&
              convertedMap.containsKey('type')) {
            importedItems.add(CaptureItem.fromMap(convertedMap));
          }
        }
      }

      // Reject transmission transaction immediately if the payload structure contains zero valid elements
      if (importedItems.isEmpty && decoded.isNotEmpty) return false;

      final box = await _getBox();
      await box.put('items', importedItems.map((e) => e.toMap()).toList());

      // Propagate state modifications cleanly across active system consumer interfaces
      state = importedItems;
      return true;
    } catch (e) {
      debugPrint('Import Handshake Exception: Transaction declined due to format anomaly -> $e');
      return false;
    }
  }

  /// Optimized batch ingestion engine capable of committing high-volume asset arrays sequentially
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

    // Splice records onto structural header to maintain chronological sequence
    state = [...newItems, ...state];

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
  }

  /// Appends a unified isolated data capture element onto the state model and local disk structure
  Future<void> insertItem(String content, String type, {String title = ''}) async {
    final newItem = CaptureItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: type,
      timestamp: DateTime.now(),
    );

    state = [newItem, ...state];

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
  }

  /// Micro-targeted element index lookup modification matching specified identifier parameters
  Future<void> updateItem(String id, String newContent, {String? title}) async {
    bool stateMutationOccurred = false;

    // Use .map() to safely update logic while returning the exact CaptureItem object
    final List<CaptureItem> updatedCollection = state.map((item) {
      if (item.id == id) {
        stateMutationOccurred = true;
        return CaptureItem(
          id: item.id,
          title: title ?? item.title,
          content: newContent,
          type: item.type,
          timestamp: item.timestamp, // Retain original transaction timeline sequence
        );
      }
      return item;
    }).toList();

    // Performance short-circuit optimization: Avoid unneeded mutations if target element matches perfectly
    if (!stateMutationOccurred) return;

    state = updatedCollection;

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
  }

  /// Detaches an explicit node block safely from system layout tracks and cleans storage indexes
  Future<void> deleteItem(String id) async {
    final int originalSize = state.length;
    final List<CaptureItem> remainingItems = state.where((item) => item.id != id).toList();

    // Terminate pipeline path early if elimination candidate wasn't registered in tracking state
    if (remainingItems.length == originalSize) return;

    state = remainingItems;

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
  }
}

// Global immutable reactive database notifier provider interface registration hook
final localDatabaseProvider = NotifierProvider<DatabaseNotifier, List<CaptureItem>>(DatabaseNotifier.new);