import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
// NOTE: verify this path — copied from the same relative import used in
// quicknote.dart and settings.dart ('../core/crypto_engine.dart'). If
// database.dart lives in a different folder than those two, adjust
// accordingly; an unresolved import will fail to compile, not fail silently.
import '../core/crypto_engine.dart';

class CaptureItem {
  final String id;
  final String title;
  final String content;
  final String type;
  final DateTime timestamp;
  final bool backupEnabled;
  final String? remoteFileId;
  final DateTime? lastSyncedTimestamp;
  final bool pendingReviewAfterSync;

  CaptureItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.timestamp,
    this.backupEnabled = false,
    this.remoteFileId,
    this.lastSyncedTimestamp,
    this.pendingReviewAfterSync = false,
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
      'lastSyncedTimestamp': lastSyncedTimestamp?.toIso8601String(),
      'pendingReviewAfterSync': pendingReviewAfterSync,
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
      lastSyncedTimestamp: map['lastSyncedTimestamp'] != null
          ? DateTime.tryParse(map['lastSyncedTimestamp'].toString())
          : null,
      pendingReviewAfterSync: map['pendingReviewAfterSync'] == true,
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
                debugPrint(
                    'System Parsing Exception: Element sequence skip occurred -> $e');
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
      final List<Map<String, dynamic>> rawList =
          state.map((item) => item.toMap()).toList();
      return jsonEncode(rawList);
    } catch (e) {
      debugPrint(
          'Export Serialization Flaw: Failed to output raw data matrices -> $e');
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
      debugPrint(
          'Import Handshake Exception: Transaction declined due to format anomaly -> $e');
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

  static String generateRemoteFileId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$hex.json';
  }

  static final RegExp _opaqueRemoteIdPattern = RegExp(r'^[0-9a-f]{32}\.json$');
  static bool isOpaqueRemoteFileId(String? value) =>
      value != null && _opaqueRemoteIdPattern.hasMatch(value);
  static String legacyNoteFileName(String title) {
    final cleaned = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '$cleaned.json';
  }

  bool titleExists(String title, {String? excludingId}) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    return state.any((item) =>
        item.id != excludingId &&
        item.title.trim().toLowerCase() == normalized);
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
    await box.put(_syncQueueKey,
        jsonEncode({'deleted': <String>[], 'renamed': <String, String>{}}));
  }

  Future<void> _queueRemoteDeletion(String fileName) async {
    final box = await _getBox();
    final queue = await _readSyncQueue(box);
    final List<String> deleted = queue['deleted'];
    final Map<String, String> renamed = queue['renamed'];

    renamed.remove(fileName);
    if (!deleted.contains(fileName)) deleted.add(fileName);

    await box.put(
        _syncQueueKey, jsonEncode({'deleted': deleted, 'renamed': renamed}));
  }

  Future<bool> insertItem(String content, String type,
      {String title = '',
      bool backupEnabled = false,
      String? remoteFileId,
      DateTime? timestamp,
      DateTime? lastSyncedTimestamp,
      bool pendingReviewAfterSync = false}) async {
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
      remoteFileId: backupEnabled
          ? (remoteFileId ?? generateRemoteFileId())
          : remoteFileId,
      lastSyncedTimestamp: lastSyncedTimestamp,
      pendingReviewAfterSync: pendingReviewAfterSync,
    );

    state = [newItem, ...state];

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
    return true;
  }

  Future<bool> updateItem(String id, String newContent,
      {String? title,
      String? type,
      bool? backupEnabled,
      String? remoteFileId,
      DateTime? timestamp,
      DateTime? lastSyncedTimestamp,
      bool? pendingReviewAfterSync}) async {
    CaptureItem? previous;
    for (final item in state) {
      if (item.id == id) {
        previous = item;
        break;
      }
    }
    if (previous == null) return false;

    final String resolvedTitle = title ?? previous.title;
    final String resolvedType = type ?? previous.type;
    final bool resolvedBackup = backupEnabled ?? previous.backupEnabled;
    final DateTime resolvedTimestamp = timestamp ?? DateTime.now();
    final DateTime? resolvedLastSynced =
        lastSyncedTimestamp ?? previous.lastSyncedTimestamp;
    final bool resolvedPendingReview =
        pendingReviewAfterSync ?? previous.pendingReviewAfterSync;
    if (resolvedBackup && resolvedTitle.trim().isEmpty) return false;
    if (resolvedBackup && titleExists(resolvedTitle, excludingId: id))
      return false;
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
          type: resolvedType,
          timestamp: resolvedTimestamp,
          backupEnabled: resolvedBackup,
          remoteFileId: resolvedRemoteFileId,
          lastSyncedTimestamp: resolvedLastSynced,
          pendingReviewAfterSync: resolvedPendingReview,
        );
      }
      return item;
    }).toList();

    if (!stateMutationOccurred) return false;

    if (previous.backupEnabled &&
        !resolvedBackup &&
        previous.remoteFileId != null) {
      await _queueRemoteDeletion(previous.remoteFileId!);
    }
    state = updatedCollection;

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());
    return true;
  }

  Future<String?> migrateLegacyRemoteFileId(String id) async {
    int index = -1;
    for (int i = 0; i < state.length; i++) {
      if (state[i].id == id) {
        index = i;
        break;
      }
    }
    if (index == -1 || isOpaqueRemoteFileId(state[index].remoteFileId))
      return null;

    final CaptureItem target = state[index];
    final String legacyName =
        target.remoteFileId ?? legacyNoteFileName(target.title);

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

  /// Re-encrypts every locally stored `encrypted_note` from `oldPin` to
  /// `newPin`, used during password rotation.
  ///
  /// `oldParams`/`newParams` must be captured and computed explicitly by
  /// the caller BEFORE calling this — see the note below on why. This
  /// method does not read `CryptoEngine`'s live, mutable KDF-tier
  /// selection at all.
  ///
  /// Why explicit parameters, not the live global tier: `CryptoEngine`'s
  /// active KDF parameters (`kdf_hardened`) can change as PART OF the
  /// same password-rotation operation that calls this method (e.g. root
  /// status was re-evaluated and differs from before). If this method
  /// read the live global instead, decrypting the OLD notes and
  /// encrypting the NEW ones could silently end up using the WRONG tier
  /// for one side of that operation, depending on exactly when
  /// `kdf_hardened` gets flipped relative to this call — producing notes
  /// that are unreadable even with the correct new password. Requiring
  /// the caller to pass both tiers explicitly makes that ordering bug
  /// structurally impossible here: this method has no way to observe
  /// `kdf_hardened` changing mid-operation, because it never looks at it.
  ///
  /// This builds a COMPLETE replacement copy of the entire `items`
  /// collection in memory first — the live `state` and the underlying
  /// Hive `items` key are never touched during preparation. Only once
  /// every encrypted note has been successfully decrypted under
  /// `oldPin`/`oldParams` and re-encrypted under `newPin`/`newParams`
  /// does this perform exactly ONE `box.put('items', ...)` write,
  /// replacing the whole collection at once. If any step fails before
  /// that single write, this returns false and neither `state` nor Hive
  /// have been modified at all — the original notes are exactly as they
  /// were, still encrypted under `oldPin`/`oldParams`, because nothing
  /// about them was ever touched.
  ///
  /// This never calls deleteItem() (which also queues a remote deletion
  /// for backup-enabled notes — the wrong behavior for a rotation) and
  /// never calls insertItem() (which mints a new id/remoteFileId and
  /// would sever the link to anything already synced under the old
  /// identity). Every field other than `content` is copied verbatim from
  /// the original item.
  ///
  /// On the "zeroing plaintext" question: the decrypted note bodies here
  /// are Dart Strings. Dart Strings are immutable and may be interned;
  /// there is no reliable way to overwrite one in place, and code that
  /// pretends to do so is decorative, not protective. The real mitigation
  /// applied here is scope minimization — each plaintext String exists
  /// only from the moment it's decrypted to the moment it's re-encrypted,
  /// held in a short-lived local variable, then allowed to go out of
  /// scope for normal garbage collection. No claim stronger than that is
  /// made or should be inferred from this code.
  Future<bool> migrateEncryptedNotes(
    String oldPin,
    String newPin, {
    required KdfParams oldParams,
    required KdfParams newParams,
  }) async {
    // Build the full replacement collection from the CURRENT live state,
    // but do not assign it to `state` or write it anywhere yet. `state`
    // itself is read once, here, and never mutated by this method until
    // the single commit at the very end.
    final List<CaptureItem> replacementCollection = [];

    for (final item in state) {
      if (item.type != 'encrypted_note') {
        // Not an encrypted note — carried into the replacement collection
        // completely unchanged.
        replacementCollection.add(item);
        continue;
      }

      final String plaintext = await CryptoEngine.decryptProcessWithParams(
          item.content, oldPin, oldParams);

      if (plaintext == 'DECRYPTION FAULT') {
        // Old pin/params didn't decrypt this note. Abort immediately —
        // nothing has been written anywhere, so the live collection and
        // Hive are both exactly as they were before this call.
        return false;
      }

      final String reEncrypted;
      try {
        reEncrypted = await CryptoEngine.encryptProcessWithParams(
            plaintext, newPin, newParams);
      } catch (_) {
        // encryptProcessWithParams throws StateError('ENCRYPTION FAILED')
        // if the underlying cipher operation fails (see crypto_isolate.dart
        // / crypto_engine.dart) — genuinely rare, but this must not
        // propagate as an uncaught exception out of this method. Caught
        // here and turned into the same controlled `false` result as
        // every other failure path in this method, so
        // _executePasswordChange() always gets back a clean bool rather
        // than sometimes getting an exception it isn't prepared to catch.
        return false;
      }

      replacementCollection.add(CaptureItem(
        id: item.id,
        title: item.title,
        content: reEncrypted,
        type: item.type,
        timestamp: item.timestamp,
        backupEnabled: item.backupEnabled,
        remoteFileId: item.remoteFileId,
        lastSyncedTimestamp: item.lastSyncedTimestamp,
        pendingReviewAfterSync: item.pendingReviewAfterSync,
      ));
    }

    if (replacementCollection.length != state.length) {
      // Defensive: the replacement collection must contain exactly one
      // entry per original item (migrated or carried over unchanged). If
      // this ever doesn't hold, abort rather than commit something that
      // could silently drop an item.
      return false;
    }

    // Every note that needed migrating has been decrypted and
    // re-encrypted successfully, and every other item was carried over
    // untouched. Commit the whole replacement collection now, in one
    // write — this is the only place this method touches `state` or Hive.
    try {
      final box = await _getBox();
      await box.put(
          'items', replacementCollection.map((e) => e.toMap()).toList());
      // Only update the in-memory state after the Hive write has
      // actually succeeded — this way, if the write throws, `state`
      // was never touched and still matches what's on disk.
      state = replacementCollection;
      return true;
    } catch (_) {
      // The Hive write itself failed. `state` was never reassigned above
      // (that only happens after a successful write), so the in-memory
      // collection still matches what's actually persisted on disk.
      // Nothing to roll back.
      return false;
    }
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

    final List<CaptureItem> remainingItems =
        state.where((item) => item.id != id).toList();
    state = remainingItems;

    final box = await _getBox();
    await box.put('items', state.map((e) => e.toMap()).toList());

    if (target.backupEnabled && target.remoteFileId != null) {
      await _queueRemoteDeletion(target.remoteFileId!);
    }
  }
}

final localDatabaseProvider =
    NotifierProvider<DatabaseNotifier, List<CaptureItem>>(DatabaseNotifier.new);
