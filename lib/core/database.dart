import 'dart:convert';
import 'dart:math';
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
  final String? remoteFileId;

  CaptureItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.timestamp,
    this.backupEnabled = false,
    this.remoteFileId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'backupEnabled': backupEnabled,
      'remoteFileId': remoteFileId,
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
      remoteFileId: map['remoteFileId'] as String?,
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

  // Stable, opaque, randomly-generated GitHub filename - deliberately
  // carries zero information about the note's title or content, unlike the
  // old title-derived scheme. Generated once per note when backup is first
  // enabled, and never changes again for that note's lifetime (a title edit
  // no longer requires a remote rename).
  static String generateRemoteFileId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$hex.json';
  }

  // Matches only properly-generated opaque ids from generateRemoteFileId().
  // Anything else stored in remoteFileId - including a legacy title-based
  // name that ended up there via a pull/restore before this note was ever
  // pushed under a fresh opaque id - is treated as still needing migration.
  static final RegExp _opaqueRemoteIdPattern = RegExp(r'^[0-9a-f]{32}\.json$');
  static bool isOpaqueRemoteFileId(String? value) => value != null && _opaqueRemoteIdPattern.hasMatch(value);

  // Legacy filename derivation - the old title-based scheme, which exposed
  // note titles in plaintext via the GitHub file listing. Kept only so
  // migration can locate and delete notes still sitting under their old
  // title-based name; never used to create new files.
  static String legacyNoteFileName(String title) {
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

  Future<bool> insertItem(String content, String type, {String title = '', bool backupEnabled = false, String? remoteFileId, DateTime? timestamp}) async {
    if (backupEnabled && title.trim().isEmpty) return false;
    if (backupEnabled && titleExists(title)) return false;

    final DateTime resolvedTimestamp = timestamp ?? DateTime.now();

    final newItem = CaptureItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: type,
      timestamp: resolvedTimestamp,
      backupEnabled: backupEnabled,
      remoteFileId: backupEnabled ? (remoteFileId ?? generateRemoteFileId()) : remoteFileId,
    );

    state = [newItem, ...state];

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
    return true;
  }

  Future<bool> updateItem(String id, String newContent, {String? title, bool? backupEnabled, String? remoteFileId, DateTime? timestamp}) async {
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
    // Defaults to "now" for a normal user edit. Callers applying a remote
    // version during conflict resolution pass the remote's own timestamp
    // explicitly instead, so it isn't misrepresented as freshly edited.
    final DateTime resolvedTimestamp = timestamp ?? DateTime.now();

    if (resolvedBackup && resolvedTitle.trim().isEmpty) return false;
    if (resolvedBackup && titleExists(resolvedTitle, excludingId: id)) return false;

    // Prefer an explicitly-supplied id (the caller may have already computed
    // one to keep the local record and the actual GitHub push perfectly in
    // sync), then fall back to whatever this item already had, and only
    // auto-generate as a last resort for callers that don't track this.
    final String? resolvedRemoteFileId = resolvedBackup
        ? (remoteFileId ?? previous.remoteFileId ?? generateRemoteFileId())
        : previous.remoteFileId;

    bool stateMutationOccurred = false;

    final List<CaptureItem> updatedCollection = state.map((item) {
      if (item.id == id) {
        stateMutationOccurred = true;
        return CaptureItem(
          id: item.id,
          title: resolvedTitle,
          content: newContent,
          type: item.type,
          timestamp: resolvedTimestamp,
          backupEnabled: resolvedBackup,
          remoteFileId: resolvedRemoteFileId,
        );
      }
      return item;
    }).toList();

    if (!stateMutationOccurred) return false;

    if (previous.backupEnabled && !resolvedBackup && previous.remoteFileId != null) {
      await _queueRemoteDeletion(previous.remoteFileId!);
    }
    // Title changes no longer require a remote rename - the remote filename
    // is a stable opaque id decoupled from the title (see generateRemoteFileId),
    // so a title-only edit is just a normal content update at the same file.

    state = updatedCollection;

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
    return true;
  }

  // One-time migration helper: assigns a fresh opaque remoteFileId to any
  // backup-enabled item that doesn't have a properly-generated one yet -
  // either it never had one (pre-remoteFileId note), or it was restored via
  // pull with its remoteFileId set to a legacy title-based name. Returns the
  // legacy filename actually sitting on GitHub right now so the caller can
  // queue it for deletion once the note is re-pushed under its new name.
  Future<String?> migrateLegacyRemoteFileId(String id) async {
    int index = -1;
    for (int i = 0; i < state.length; i++) {
      if (state[i].id == id) {
        index = i;
        break;
      }
    }
    if (index == -1 || isOpaqueRemoteFileId(state[index].remoteFileId)) return null;

    final CaptureItem target = state[index];
    final String legacyName = target.remoteFileId ?? legacyNoteFileName(target.title);

    final CaptureItem migrated = CaptureItem(
      id: target.id,
      title: target.title,
      content: target.content,
      type: target.type,
      timestamp: target.timestamp,
      backupEnabled: target.backupEnabled,
      remoteFileId: generateRemoteFileId(),
    );

    final List<CaptureItem> newState = List<CaptureItem>.from(state);
    newState[index] = migrated;
    state = newState;

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());

    return legacyName;
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

    if (target.backupEnabled && target.remoteFileId != null) {
      await _queueRemoteDeletion(target.remoteFileId!);
    }
  }
}

final localDatabaseProvider = NotifierProvider<DatabaseNotifier, List<CaptureItem>>(DatabaseNotifier.new);