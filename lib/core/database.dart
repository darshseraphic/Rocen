import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory representation only. Persistent serialization is intentionally
/// absent until the approved final Stage 6 note ciphertext envelope exists.
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
}

/// Protected application-data persistence is deliberately fail-closed during
/// Block B. The final Stage 6 ciphertext envelope is not present in this
/// source tree, so all user-entered notes, note titles, imported media paths,
/// TODO text, and workspace exports/imports are classified as protected
/// application data and are not persisted or exported.
///
/// Non-sensitive settings/security metadata is stored separately in
/// `rocen_settings_box`; this provider is not that metadata store.
const bool protectedApplicationPersistenceAvailable = false;

class DatabaseNotifier extends Notifier<List<CaptureItem>> {
  static const String protectedPersistenceUnavailableMessage =
      'Protected application-data persistence is unavailable until the approved '
      'Stage 6 ciphertext envelope is implemented. The operation was not saved.';

  @override
  List<CaptureItem> build() => <CaptureItem>[];

  bool titleExists(String title, {String? excludingId}) {
    final String normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    return state.any(
      (item) =>
          item.id != excludingId &&
          item.title.trim().toLowerCase() == normalized,
    );
  }

  Future<bool> insertMultipleItems(List<String> filePaths, String type) async {
    return false;
  }

  Future<bool> insertItem(
    String content,
    String type, {
    String title = '',
    bool backupEnabled = false,
    String? remoteFileId,
    DateTime? timestamp,
    DateTime? lastSyncedTimestamp,
    bool pendingReviewAfterSync = false,
  }) async {
    return false;
  }

  Future<bool> updateItem(
    String id,
    String newContent, {
    String? title,
    String? type,
    bool? backupEnabled,
    String? remoteFileId,
    DateTime? timestamp,
    DateTime? lastSyncedTimestamp,
    bool? pendingReviewAfterSync,
  }) async {
    return false;
  }

  Future<bool> deleteItem(String id) async {
    return false;
  }

  String exportToSchemaJson() => '[]';

  Future<bool> importFromSchemaJson(String jsonRawString) async => false;
}

final localDatabaseProvider =
    NotifierProvider<DatabaseNotifier, List<CaptureItem>>(DatabaseNotifier.new);
