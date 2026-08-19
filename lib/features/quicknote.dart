import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/database.dart';
import '../core/crypto_engine.dart';
import '../core/github_backup_service.dart';
import '../core/debug_log.dart';
import '../main.dart';

const String _kTitleBodySeparator = '\u0000\u0000ROCEN_TITLE_SPLIT\u0000\u0000';

String _combineTitleAndBody(String title, String body) => '$title$_kTitleBodySeparator$body';

({String title, String body}) _splitTitleAndBody(String combined) {
  final int idx = combined.indexOf(_kTitleBodySeparator);
  if (idx == -1) return (title: '', body: combined);
  return (
  title: combined.substring(0, idx),
  body: combined.substring(idx + _kTitleBodySeparator.length),
  );
}

class SecurityUiTheme {
  final bool isDark;
  late final Color textMain;
  late final Color textSub;
  late final Color borderColor;
  late final Color dialogBg;
  late final Color ruleBorder;

  SecurityUiTheme(this.isDark) {
    textMain = isDark ? Colors.white : Colors.black;
    textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
  }
}

void showMissingKeyUiDialog(BuildContext context, bool isDark, {String? message}) {
  final theme = SecurityUiTheme(isDark);
  final String bodyMessage = message ?? 'SET KEY FIRST FROM SETTINGS TO USE THIS FEATURE';
  final Color buttonBg = isDark ? Colors.white : Colors.black;
  final Color buttonText = isDark ? Colors.black : Colors.white;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    pageBuilder: (context, anim1, anim2) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.dialogBg,
              border: Border.all(color: theme.borderColor, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'SECURITY LOCK OUTCAST',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                ),
                const SizedBox(height: 16),
                Text(
                  bodyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5, letterSpacing: 0.02, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: buttonBg,
                    child: Text('ACKNOWLEDGE', style: TextStyle(color: buttonText, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

void showAcknowledgeDialog(BuildContext context, bool isDark, String title, String message) {
  final theme = SecurityUiTheme(isDark);
  final Color buttonBg = isDark ? Colors.white : Colors.black;
  final Color buttonText = isDark ? Colors.black : Colors.white;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    pageBuilder: (context, anim1, anim2) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.dialogBg,
              border: Border.all(color: theme.borderColor, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5, letterSpacing: 0.02, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: buttonBg,
                    child: Text('ACKNOWLEDGE', style: TextStyle(color: buttonText, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> attemptGithubSync(WidgetRef ref, {Map<String, String>? upsert}) async {
  try {
    final settingsBox = Hive.box('rocen_settings_box');
    final String? globalPin = settingsBox.get('system_crypto_pin');
    final String? accessBlob = settingsBox.get('github_access_encrypted');
    if (globalPin == null || globalPin.isEmpty || accessBlob == null) {
      secureDebugLog('GITHUB SYNC ABORTED: missing PIN or stored access blob (globalPin null/empty: ${globalPin == null || globalPin.isEmpty}, accessBlob null: ${accessBlob == null})');
      return;
    }

    final String? unwrappedAccessBlob = await CryptoEngine.hardwareUnwrap(accessBlob, keyAlias: CryptoEngine.githubTokenKeyAlias);
    final String accessJson = await CryptoEngine.decryptProcess(unwrappedAccessBlob ?? accessBlob, globalPin);
    if (accessJson == 'DECRYPTION FAULT') {
      secureDebugLog('GITHUB SYNC ABORTED: stored access blob failed to decrypt with the current PIN');
      return;
    }
    final Map<String, dynamic> access = jsonDecode(accessJson);
    final String? token = access['token'] as String?;
    final String? repo = access['repo'] as String?;
    if (token == null || token.isEmpty || repo == null || repo.isEmpty) {
      secureDebugLog('GITHUB SYNC ABORTED: token or repo field empty after decrypt (token empty: ${token == null || token.isEmpty}, repo empty: ${repo == null || repo.isEmpty})');
      return;
    }

    secureDebugLog('GITHUB SYNC STARTING: repo="$repo" upsertKeys=${upsert?.keys.toList()}');

    final service = GithubBackupService(token: token, repoPath: repo);
    final notifier = ref.read(localDatabaseProvider.notifier);
    final queue = await notifier.getSyncQueue();
    secureDebugLog('GITHUB SYNC QUEUE: deleted=${queue['deleted']} renamed=${queue['renamed']}');

    await service.amendSync(
      upsertFiles: upsert ?? const {},
      deleteFiles: List<String>.from(queue['deleted']),
      renameFiles: Map<String, String>.from(queue['renamed']),
    );

    await notifier.clearSyncQueue();
    secureDebugLog('GITHUB SYNC SUCCEEDED');
  } catch (e, stackTrace) {
    secureDebugLog('GITHUB SYNC FAILED: $e');
    secureDebugLog('$stackTrace');
  }
}

Future<String?> pushAllBackupEnabledNotes(WidgetRef ref) async {
  try {
    final settingsBox = Hive.box('rocen_settings_box');
    final String? globalPin = settingsBox.get('system_crypto_pin');
    final String? accessBlob = settingsBox.get('github_access_encrypted');
    if (globalPin == null || accessBlob == null) {
      return 'GITHUB CREDENTIALS ARE MISSING LOCALLY.';
    }

    final String? unwrappedAccessBlob = await CryptoEngine.hardwareUnwrap(accessBlob, keyAlias: CryptoEngine.githubTokenKeyAlias);
    final String accessJson = await CryptoEngine.decryptProcess(unwrappedAccessBlob ?? accessBlob, globalPin);
    if (accessJson == 'DECRYPTION FAULT') {
      return 'STORED GITHUB CREDENTIALS COULD NOT BE DECRYPTED WITH THE CURRENT PASSWORD. RE-ENTER YOUR TOKEN IN GITHUB TOKEN STORE.';
    }
    final Map<String, dynamic> access = jsonDecode(accessJson);
    final String? token = access['token'] as String?;
    final String? repo = access['repo'] as String?;
    if (token == null || repo == null) {
      return 'STORED TOKEN OR REPOSITORY WAS EMPTY.';
    }

    final backedUpItems = ref.read(localDatabaseProvider).where((item) => item.backupEnabled).toList();
    final notifier = ref.read(localDatabaseProvider.notifier);

    final Map<String, String> upsertFiles = {};
    final List<String> legacyFilesToDelete = [];
    final List<({String id, DateTime timestamp})> pushedItems = [];

    for (final item in backedUpItems) {
      try {
        String? remoteId = item.remoteFileId;
        if (!DatabaseNotifier.isOpaqueRemoteFileId(remoteId)) {
          // Either this note was synced before remoteFileId existed, or it
          // was restored via pull and ended up with a legacy title-based
          // name - either way, it's still sitting on GitHub under a
          // title-exposing filename. Assign it a fresh opaque id now and
          // queue the old file for deletion once re-pushed under the new one.
          final String? legacyName = await notifier.migrateLegacyRemoteFileId(item.id);
          if (legacyName != null) legacyFilesToDelete.add(legacyName);
          final CaptureItem refreshed = ref.read(localDatabaseProvider).firstWhere((e) => e.id == item.id);
          remoteId = refreshed.remoteFileId;
        }
        if (remoteId == null) continue;

        final Map<String, String> fields;
        if (item.type == 'encrypted_note') {
          if (item.pendingReviewAfterSync) {
            // Content is already the exact combined-encrypted package from a
            // zero-decrypt swap and hasn't been reopened since - push it
            // through unchanged. Decrypting and re-combining here would
            // double-embed the title inside content that already has one.
            fields = {...CryptoEngine.splitForBackup(item.content), 'timestamp': item.timestamp.toIso8601String()};
          } else {
            final String decryptedBody = await CryptoEngine.decryptProcess(item.content, globalPin);
            if (decryptedBody == 'DECRYPTION FAULT') {
              secureDebugLog('SKIPPING NOTE "${item.title}" - COULD NOT DECRYPT FOR RE-PACKAGING');
              continue;
            }
            final String combined = _combineTitleAndBody(item.title, decryptedBody);
            final String reEncrypted = await CryptoEngine.encryptProcess(combined, globalPin);
            fields = {...CryptoEngine.splitForBackup(reEncrypted), 'timestamp': item.timestamp.toIso8601String()};
          }
        } else {
          fields = {'salt': '', 'nonce': '', 'cyphertext': _combineTitleAndBody(item.title, item.content), 'timestamp': item.timestamp.toIso8601String()};
        }
        upsertFiles[remoteId] = jsonEncode(fields);
        pushedItems.add((id: item.id, timestamp: item.timestamp));
      } catch (e) {
        secureDebugLog('SKIPPING CORRUPTED NOTE "${item.title}" DURING PUSH: $e');
        continue;
      }
    }

    final service = GithubBackupService(token: token, repoPath: repo);
    final queue = await notifier.getSyncQueue();
    final List<String> deleteList = [...List<String>.from(queue['deleted']), ...legacyFilesToDelete];

    await service.amendSync(
      upsertFiles: upsertFiles,
      deleteFiles: deleteList,
      renameFiles: Map<String, String>.from(queue['renamed']),
      message: 'refresh sync',
    );

    // Mark every successfully-pushed note as caught up as of its own current
    // timestamp - this becomes the new "last known common state" baseline
    // for zero-decrypt conflict detection on the next pull.
    for (final pushed in pushedItems) {
      await notifier.updateItem(
        pushed.id,
        ref.read(localDatabaseProvider).firstWhere((e) => e.id == pushed.id).content,
        timestamp: pushed.timestamp,
        lastSyncedTimestamp: pushed.timestamp,
      );
    }

    await notifier.clearSyncQueue();
    return null;
  } catch (e) {
    return 'GITHUB PUSH FAILED: $e';
  }
}

class NoteConflict {
  final String localId;
  final String title;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
  final String remoteFileId;
  final String remoteType;
  final String remoteSalt;
  final String remoteNonce;
  final String remoteCyphertext;

  NoteConflict({
    required this.localId,
    required this.title,
    required this.localTimestamp,
    required this.remoteTimestamp,
    required this.remoteFileId,
    required this.remoteType,
    required this.remoteSalt,
    required this.remoteNonce,
    required this.remoteCyphertext,
  });
}

class PullResult {
  final int syncedCount;
  final List<NoteConflict> conflicts;
  PullResult({required this.syncedCount, required this.conflicts});
}

// Applies a remote note's raw (still-encrypted, for locked notes) payload
// directly to local storage with zero decryption - a byte-level ciphertext
// copy for locked notes, a plain string split (no cryptographic operation)
// for unlocked ones. The note's local plaintext title is deliberately left
// untouched; pendingReviewAfterSync marks that its content may no longer
// match that title until the note is actually reopened.
Future<void> _applyRemoteSwap(
    DatabaseNotifier notifier, {
      required String localId,
      required String remoteFileId,
      required String remoteType,
      required String salt,
      required String nonce,
      required String cyphertext,
      required DateTime remoteTimestamp,
    }) async {
  final String newContent = salt.isEmpty
      ? _splitTitleAndBody(cyphertext).body
      : CryptoEngine.mergeFromBackup(salt, nonce, cyphertext);

  await notifier.updateItem(
    localId,
    newContent,
    type: remoteType,
    backupEnabled: true,
    remoteFileId: remoteFileId,
    timestamp: remoteTimestamp,
    lastSyncedTimestamp: remoteTimestamp,
    pendingReviewAfterSync: true,
  );
}

Future<PullResult?> pullAndReconcileNotes(WidgetRef ref) async {
  try {
    final settingsBox = Hive.box('rocen_settings_box');
    final String? globalPin = settingsBox.get('system_crypto_pin');
    final String? accessBlob = settingsBox.get('github_access_encrypted');
    if (globalPin == null || accessBlob == null) return null;

    final String? unwrappedAccessBlob = await CryptoEngine.hardwareUnwrap(accessBlob, keyAlias: CryptoEngine.githubTokenKeyAlias);
    final String accessJson = await CryptoEngine.decryptProcess(unwrappedAccessBlob ?? accessBlob, globalPin);
    if (accessJson == 'DECRYPTION FAULT') return null;
    final Map<String, dynamic> access = jsonDecode(accessJson);
    final String? token = access['token'] as String?;
    final String? repo = access['repo'] as String?;
    if (token == null || repo == null) return null;

    final service = GithubBackupService(token: token, repoPath: repo);
    final List<String> filesToImport = await service.listNoteFiles();
    filesToImport.remove('device_key.json');

    final notifier = ref.read(localDatabaseProvider.notifier);
    final currentBackedUpItems = ref.read(localDatabaseProvider).where((item) => item.backupEnabled).toList();

    final Map<String, CaptureItem> localByRemoteId = {
      for (final item in currentBackedUpItems)
        if (item.remoteFileId != null) item.remoteFileId!: item,
    };
    final Set<String> matchedIds = {};
    final List<NoteConflict> conflicts = [];

    await notifier.clearSyncQueue();

    int syncedCount = 0;
    for (final fileName in filesToImport) {
      try {
        final Map<String, dynamic>? data = await service.fetchNoteFile(fileName);
        if (data == null) continue;

        final String salt = (data['salt'] ?? '').toString();
        final String nonce = (data['nonce'] ?? '').toString();
        final String cyphertext = (data['cyphertext'] ?? '').toString();
        final DateTime remoteTimestamp = DateTime.tryParse((data['timestamp'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final String remoteType = salt.isEmpty ? 'note' : 'encrypted_note';

        final CaptureItem? existing = localByRemoteId[fileName];

        if (existing == null) {
          // Genuinely new note from another device - there's no local
          // counterpart to compare against or preserve a title for, so this
          // is the one case that still requires an actual decrypt (same as
          // opening any note for the first time would).
          String noteTitle;
          String localReadyContent;
          if (salt.isEmpty) {
            final split = _splitTitleAndBody(cyphertext);
            noteTitle = split.title;
            localReadyContent = split.body;
          } else {
            final String merged = CryptoEngine.mergeFromBackup(salt, nonce, cyphertext);
            final String decryptedCombined = await CryptoEngine.decryptProcess(merged, globalPin);
            if (decryptedCombined == 'DECRYPTION FAULT') continue;
            final split = _splitTitleAndBody(decryptedCombined);
            noteTitle = split.title;
            localReadyContent = await CryptoEngine.encryptProcess(split.body, globalPin);
          }
          if (noteTitle.trim().isEmpty) {
            noteTitle = fileName.endsWith('.json') ? fileName.substring(0, fileName.length - 5) : fileName;
          }

          final bool inserted = await notifier.insertItem(
            localReadyContent, remoteType,
            title: noteTitle, backupEnabled: true, remoteFileId: fileName,
            timestamp: remoteTimestamp, lastSyncedTimestamp: remoteTimestamp,
          );
          if (inserted) syncedCount++;
          continue;
        }

        if (matchedIds.contains(existing.id)) continue;
        matchedIds.add(existing.id);

        // Zero-decrypt three-way comparison: everything here is plain
        // timestamp metadata, never note content.
        final DateTime? lastSynced = existing.lastSyncedTimestamp;

        if (lastSynced == null) {
          // No sync history for this note yet (pre-existing note, or first
          // pull since this tracking was added) - fall back to a simple
          // newest-wins fast-forward rather than flagging every note as a
          // conflict on the first run after this update.
          if (remoteTimestamp.isAfter(existing.timestamp)) {
            await _applyRemoteSwap(
              notifier, localId: existing.id, remoteFileId: fileName, remoteType: remoteType,
              salt: salt, nonce: nonce, cyphertext: cyphertext, remoteTimestamp: remoteTimestamp,
            );
            syncedCount++;
          }
          continue;
        }

        final bool localChanged = existing.timestamp.isAfter(lastSynced);
        final bool remoteChanged = remoteTimestamp.isAfter(lastSynced);

        if (!localChanged && !remoteChanged) continue; // nothing to do

        if (!localChanged && remoteChanged) {
          // Clean fast-forward - local hasn't diverged, safe to auto-apply.
          await _applyRemoteSwap(
            notifier, localId: existing.id, remoteFileId: fileName, remoteType: remoteType,
            salt: salt, nonce: nonce, cyphertext: cyphertext, remoteTimestamp: remoteTimestamp,
          );
          syncedCount++;
          continue;
        }

        if (localChanged && !remoteChanged) {
          // Local is ahead; the next push will bring GitHub up to date.
          continue;
        }

        // Both sides changed independently since the last known sync point -
        // a genuine conflict. Title shown is always the LOCAL title, since
        // the remote title is never decrypted at this stage.
        conflicts.add(NoteConflict(
          localId: existing.id,
          title: existing.title,
          localTimestamp: existing.timestamp,
          remoteTimestamp: remoteTimestamp,
          remoteFileId: fileName,
          remoteType: remoteType,
          remoteSalt: salt,
          remoteNonce: nonce,
          remoteCyphertext: cyphertext,
        ));
      } catch (_) {
        continue;
      }
    }

    for (final item in currentBackedUpItems) {
      if (!matchedIds.contains(item.id)) {
        await notifier.deleteItem(item.id);
      }
    }

    return PullResult(syncedCount: syncedCount, conflicts: conflicts);
  } catch (_) {
    return null;
  }
}

class RefreshFailure implements Exception {
  final String message;
  RefreshFailure(this.message);
}

String _formatTimeAgo(DateTime timestamp) {
  final Duration diff = DateTime.now().difference(timestamp);
  if (diff.inMinutes < 1) return 'JUST NOW';
  if (diff.inMinutes < 60) return '${diff.inMinutes} MIN AGO';
  if (diff.inHours < 24) return '${diff.inHours} HR AGO';
  if (diff.inDays < 30) return '${diff.inDays} DAY${diff.inDays == 1 ? '' : 'S'} AGO';
  return '${(diff.inDays / 30).floor()} MO AGO';
}

// Sync-conflict resolution dialog - only ever shown when pullAndReconcileNotes
// found notes that exist on both this device and GitHub with genuinely
// different content. No Cancel button by design: unchecked notes simply stay
// as their local version (nothing happens to them), checked notes get
// replaced with the GitHub version - either way every note ends up
// consistent, so there's nothing a "cancel" would meaningfully undo.
Future<void> showConflictResolutionDialog(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    List<NoteConflict> conflicts,
    ) async {
  final theme = SecurityUiTheme(isDark);
  final Set<String> selectedForReplace = {};

  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    pageBuilder: (dialogContext, anim1, anim2) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 320,
                constraints: const BoxConstraints(maxHeight: 480),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.dialogBg,
                  border: Border.all(color: theme.borderColor, width: 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SYNC CONFLICTS FOUND',
                      style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'THESE NOTES DIFFER BETWEEN THIS DEVICE AND YOUR BACKUP. CHECK ANY NOTE YOU WANT REPLACED WITH THE BACKUP VERSION - LEAVE UNCHECKED TO KEEP WHAT\'S ON THIS DEVICE.',
                      style: TextStyle(color: theme.textMain, fontSize: 11, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: conflicts.map((c) {
                            final bool isSelected = selectedForReplace.contains(c.remoteFileId);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  setDialogState(() {
                                    if (isSelected) {
                                      selectedForReplace.remove(c.remoteFileId);
                                    } else {
                                      selectedForReplace.add(c.remoteFileId);
                                    }
                                  });
                                },
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      width: 18,
                                      height: 18,
                                      margin: const EdgeInsets.only(top: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected ? theme.textMain : Colors.transparent,
                                        border: Border.all(color: theme.textMain, width: 1.2),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.title.isEmpty ? '(UNTITLED)' : c.title,
                                            style: TextStyle(color: theme.textMain, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'THIS DEVICE: ${_formatTimeAgo(c.localTimestamp)}   ·   BACKUP: ${_formatTimeAgo(c.remoteTimestamp)}',
                                            style: TextStyle(color: theme.textMain.withOpacity(0.6), fontSize: 9, letterSpacing: 0.02),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: () async {
                        final notifier = ref.read(localDatabaseProvider.notifier);
                        for (final c in conflicts) {
                          if (selectedForReplace.contains(c.remoteFileId)) {
                            await _applyRemoteSwap(
                              notifier,
                              localId: c.localId,
                              remoteFileId: c.remoteFileId,
                              remoteType: c.remoteType,
                              salt: c.remoteSalt,
                              nonce: c.remoteNonce,
                              cyphertext: c.remoteCyphertext,
                              remoteTimestamp: c.remoteTimestamp,
                            );
                          }
                          // Unselected conflicts are left exactly as they are -
                          // the local version stays, nothing to do here.
                        }

                        if (dialogContext.mounted) Navigator.pop(dialogContext);

                        // Push the final resolved state back to GitHub, so the
                        // notes the user chose to KEEP LOCAL also overwrite
                        // whatever was on GitHub - otherwise the very next
                        // refresh would hit this exact same conflict again.
                        await pushAllBackupEnabledNotes(ref);

                        if (context.mounted) {
                          showAcknowledgeDialog(
                            context, isDark, 'CONFLICTS RESOLVED',
                            '${selectedForReplace.length} NOTE${selectedForReplace.length == 1 ? '' : 'S'} REPLACED WITH BACKUP. YOUR CHOICES HAVE BEEN SYNCED.',
                          );
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        color: isDark ? Colors.white : Colors.black,
                        child: Text(
                          'ACCEPTANCE',
                          style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> performRefresh(
    WidgetRef ref,
    BuildContext context, {
      bool silent = false,
      void Function(String phase)? onPhase,
    }) async {
  final isDark = ref.read(themeProvider);
  List<NoteConflict>? pendingConflicts;

  try {
    onPhase?.call('FETCH');

    final bool online = await hasInternetConnection();
    if (!online) {
      onPhase?.call('REFRESH');
      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'YOU ARE OFFLINE', 'CONNECT TO THE INTERNET TO REFRESH YOUR BACKUP.');
      }
      return;
    }

    final settingsBox = Hive.box('rocen_settings_box');
    final bool configured = settingsBox.get('system_crypto_pin') != null && settingsBox.get('github_access_encrypted') != null;
    if (!configured) {
      onPhase?.call('REFRESH');
      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'GITHUB NOT CONFIGURED', 'SET UP THE GITHUB TOKEN STORE IN SETTINGS FIRST.');
      }
      return;
    }

    const int cooldownMillis = 5000;
    final int? lastCompletedAt = settingsBox.get('last_refresh_completed_at');
    if (lastCompletedAt != null) {
      final int elapsed = DateTime.now().millisecondsSinceEpoch - lastCompletedAt;
      if (elapsed < cooldownMillis) {
        onPhase?.call('REFRESH');
        if (!silent && context.mounted) {
          final int remainingSeconds = ((cooldownMillis - elapsed) / 1000).ceil();
          showAcknowledgeDialog(
            context,
            isDark,
            'PLEASE WAIT',
            'YOU CAN REFRESH AGAIN IN $remainingSeconds SECONDS.',
          );
        }
        return;
      }
    }

    Future<void> runSync() async {
      final String? pushError = await pushAllBackupEnabledNotes(ref);
      if (pushError != null) throw RefreshFailure(pushError);

      onPhase?.call('DECRYPT');
      final PullResult? result = await pullAndReconcileNotes(ref);
      if (result == null) throw RefreshFailure('COULD NOT FETCH YOUR BACKUP FROM GITHUB.');

      onPhase?.call('SUCCESS');

      if (result.conflicts.isNotEmpty) {
        // Hand off to the conflict dialog outside the network timeout below -
        // this is now waiting on a human decision, not a network call.
        pendingConflicts = result.conflicts;
        return;
      }

      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'REFRESH COMPLETE', 'YOUR NOTES ARE UP TO DATE (${result.syncedCount} FROM BACKUP).');
      }
    }

    try {
      await runSync().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await settingsBox.put('last_refresh_completed_at', DateTime.now().millisecondsSinceEpoch);
      onPhase?.call('REFRESH');
      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'CONNECTION TOO SLOW', 'YOUR INTERNET CONNECTION IS SLOW. PLEASE TRY AGAIN.');
      }
      return;
    } on RefreshFailure catch (f) {
      await settingsBox.put('last_refresh_completed_at', DateTime.now().millisecondsSinceEpoch);
      onPhase?.call('REFRESH');
      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'REFRESH FAILED', f.message);
      }
      return;
    }

    await settingsBox.put('last_refresh_completed_at', DateTime.now().millisecondsSinceEpoch);
    await Future.delayed(const Duration(milliseconds: 900));
    onPhase?.call('REFRESH');

    // Conflicts are surfaced regardless of `silent` - unlike the purely
    // informational dialogs above, this requires an actual decision, so it
    // isn't something a background/auto refresh should suppress and lose.
    if (pendingConflicts != null && pendingConflicts!.isNotEmpty && context.mounted) {
      await showConflictResolutionDialog(context, ref, isDark, pendingConflicts!);
    }
  } catch (e) {
    secureDebugLog('REFRESH UNCAUGHT EXCEPTION: $e');
    try {
      await Hive.box('rocen_settings_box').put('last_refresh_completed_at', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
    }
    onPhase?.call('REFRESH');
    if (!silent && context.mounted) {
      showAcknowledgeDialog(context, isDark, 'REFRESH ERROR', 'UNEXPECTED ERROR: $e');
    }
  }
}

Future<bool> hasInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('github.com').timeout(const Duration(seconds: 4));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

class QuickNoteScreen extends ConsumerStatefulWidget {
  const QuickNoteScreen({super.key});

  @override
  ConsumerState<QuickNoteScreen> createState() => _QuickNoteScreenState();
}

class _QuickNoteScreenState extends ConsumerState<QuickNoteScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _isNoteLocked = false;
  bool _isBackupEnabled = false;
  Timer? _titleCheckDebounce;
  String? _titleCheckStatus;
  String _refreshLabel = 'REFRESH';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _bodyController = TextEditingController();
    _titleController.addListener(_onTitleChanged);
    _enforceKeyRotationPurge();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        performRefresh(
          ref,
          context,
          silent: true,
          onPhase: (phase) {
            if (mounted) setState(() => _refreshLabel = phase);
          },
        );
      }
    });
  }

  @override
  void dispose() {
    _titleCheckDebounce?.cancel();
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    _titleCheckDebounce?.cancel();
    final String title = _titleController.text.trim();

    if (!_isBackupEnabled || title.isEmpty) {
      if (_titleCheckStatus != null) setState(() => _titleCheckStatus = null);
      return;
    }

    setState(() => _titleCheckStatus = 'FETCHING');

    _titleCheckDebounce = Timer(const Duration(seconds: 5), () {
      _performTitleCheck(title);
    });
  }

  Future<void> _performTitleCheck(String title) async {
    // Remote uniqueness can no longer be cheaply checked - GitHub filenames
    // are now opaque random ids with no relationship to title, so there's
    // no single targeted lookup to make. Local uniqueness (this device) is
    // still enforced; duplicate titles across un-synced devices are now
    // simply allowed, since each note is identified by its own stable
    // remoteFileId regardless of title.
    final bool taken = ref.read(localDatabaseProvider.notifier).titleExists(title);
    if (mounted) setState(() => _titleCheckStatus = taken ? 'TAKEN' : 'AVAILABLE');
  }

  void _enforceKeyRotationPurge() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsBox = Hive.box('rocen_settings_box');
      final String? currentPin = settingsBox.get('system_crypto_pin');
      final String? lastActivePin = settingsBox.get('last_active_crypto_pin_snapshot');

      if (currentPin != lastActivePin) {
        _executeWipeSequence();
        settingsBox.put('last_active_crypto_pin_snapshot', currentPin);
      }
    });
  }

  void _executeWipeSequence() {
    final currentItems = ref.read(localDatabaseProvider);
    final targetsToPurge = currentItems.where((item) => item.type == 'encrypted_note').toList();

    for (var target in targetsToPurge) {
      ref.read(localDatabaseProvider.notifier).deleteItem(target.id);
    }
  }

  String? _checkLockoutViolation(Box settingsBox) {
    final int lockoutUntil = settingsBox.get('secure_lockout_until', defaultValue: 0);
    final int currentTime = DateTime.now().millisecondsSinceEpoch;

    if (lockoutUntil > currentTime) {
      final remainingTime = ((lockoutUntil - currentTime) / 1000).ceil();
      return 'SYSTEM LOCKED - WAIT $remainingTime SECONDS';
    }
    return null;
  }

  Future<void> _compileAndSaveNote() async {
    final String cleanBody = _bodyController.text.trim();
    final String cleanTitle = _titleController.text.trim();
    if (cleanBody.isEmpty) return;

    final isDark = ref.read(themeProvider);
    String finalPayload = cleanBody;
    final String? globalPin = Hive.box('rocen_settings_box').get('system_crypto_pin');

    if (_isNoteLocked) {
      if (globalPin == null || globalPin.isEmpty) {
        showMissingKeyUiDialog(context, isDark);
        return;
      }
      finalPayload = await CryptoEngine.encryptProcess(cleanBody, globalPin);
    }

    if (_isBackupEnabled) {
      final settingsBox = Hive.box('rocen_settings_box');
      final bool githubReady = settingsBox.get('github_access_encrypted') != null;

      if (!githubReady) {
        showMissingKeyUiDialog(context, isDark, message: 'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
        return;
      }

      if (cleanTitle.isEmpty) {
        showAcknowledgeDialog(context, isDark, 'BACKUP REQUIRES A TITLE', 'ENTER A NOTE TITLE BEFORE ENABLING BACKUP.');
        return;
      }

      if (ref.read(localDatabaseProvider.notifier).titleExists(cleanTitle)) {
        showAcknowledgeDialog(context, isDark, 'TITLE ALREADY TAKEN', 'CHOOSE A DIFFERENT NOTE TITLE.');
        return;
      }
    }

    final String? generatedRemoteId = _isBackupEnabled ? DatabaseNotifier.generateRemoteFileId() : null;
    final DateTime saveTimestamp = DateTime.now();

    final bool inserted = await ref.read(localDatabaseProvider.notifier).insertItem(
      finalPayload,
      _isNoteLocked ? 'encrypted_note' : 'note',
      title: cleanTitle,
      backupEnabled: _isBackupEnabled,
      remoteFileId: generatedRemoteId,
      timestamp: saveTimestamp,
    );

    if (!inserted) return;

    if (_isBackupEnabled && generatedRemoteId != null) {
      final String combined = _combineTitleAndBody(cleanTitle, cleanBody);
      final Map<String, String> backupFields = _isNoteLocked
          ? {...CryptoEngine.splitForBackup(await CryptoEngine.encryptProcess(combined, globalPin!)), 'timestamp': saveTimestamp.toIso8601String()}
          : {'salt': '', 'nonce': '', 'cyphertext': combined, 'timestamp': saveTimestamp.toIso8601String()};

      await attemptGithubSync(
        ref,
        upsert: {generatedRemoteId: jsonEncode(backupFields)},
      );
    }

    _titleController.clear();
    _bodyController.clear();
    setState(() {
      _isNoteLocked = false;
      _isBackupEnabled = false;
    });
    FocusScope.of(context).unfocus();

    Hive.box('rocen_settings_box').put('last_active_crypto_pin_snapshot', globalPin);
  }

  void _promptForPinChallenge(CaptureItem item, bool isDark, {bool openForEditing = false}) {
    final BuildContext screenContext = context;
    final settingsBox = Hive.box('rocen_settings_box');
    final String? globalPin = settingsBox.get('system_crypto_pin');

    if (globalPin == null || globalPin.isEmpty) {
      showMissingKeyUiDialog(context, isDark);
      return;
    }

    final theme = SecurityUiTheme(isDark);
    final TextEditingController pinVerifyController = TextEditingController();

    bool hasPinFailed = false;
    String? lockStringStatus = _checkLockoutViolation(settingsBox);
    Timer? countdownTimer;

    void ensureCountdownRunning(void Function(void Function()) setState_) {
      if (lockStringStatus == null) return;
      if (countdownTimer != null && countdownTimer!.isActive) return;
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final String? current = _checkLockoutViolation(settingsBox);
        setState_(() {
          lockStringStatus = current;
        });
        if (current == null) {
          timer.cancel();
        }
      });
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            ensureCountdownRunning(setDialogState);
            String displayHeaderTitle = 'ENTER 8-CHARACTER PASSWORD';
            if (lockStringStatus != null) {
              displayHeaderTitle = lockStringStatus!;
            } else if (hasPinFailed) {
              displayHeaderTitle = 'INVALID PASSWORD - TRY AGAIN';
            }

            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.dialogBg,
                    border: Border.all(color: theme.borderColor, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          displayHeaderTitle,
                          style: TextStyle(
                              color: (hasPinFailed || lockStringStatus != null) ? const Color(0xFFEF4444) : theme.textMain,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.05
                          )
                      ),
                      const SizedBox(height: 20),

                      Stack(
                        children: [
                          Opacity(
                            opacity: 0.0,
                            child: TextField(
                              controller: pinVerifyController,
                              keyboardType: TextInputType.text,
                              maxLength: 8,
                              autofocus: lockStringStatus == null,
                              enabled: lockStringStatus == null,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (hasPinFailed) {
                                    hasPinFailed = false;
                                  }
                                });
                              },
                              decoration: const InputDecoration(
                                counterText: '',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(8, (index) {
                                final String text = pinVerifyController.text;
                                bool isFilled = text.length > index;
                                bool isCurrentFocus = text.length == index;

                                Color currentBoxBorderColor;
                                if (hasPinFailed || lockStringStatus != null) {
                                  currentBoxBorderColor = const Color(0xFFEF4444);
                                } else if (isCurrentFocus) {
                                  currentBoxBorderColor = theme.textMain;
                                } else {
                                  currentBoxBorderColor = isFilled ? theme.textMain.withOpacity(0.6) : theme.borderColor;
                                }

                                return Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(
                                      color: currentBoxBorderColor,
                                      width: isCurrentFocus || hasPinFailed || lockStringStatus != null ? 1.2 : 0.8,
                                    ),
                                  ),
                                  child: isFilled
                                      ? Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: (hasPinFailed || lockStringStatus != null) ? const Color(0xFFEF4444) : theme.textMain,
                                    ),
                                  )
                                      : const SizedBox.shrink(),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.borderColor, width: 0.8),
                              ),
                              child: Text('CANCEL', style: TextStyle(color: isDark ? const Color(0xFF888888) : const Color(0xFF525252), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () async {
                              final activeLockCheck = _checkLockoutViolation(settingsBox);
                              if (activeLockCheck != null) {
                                setDialogState(() {
                                  lockStringStatus = activeLockCheck;
                                });
                                return;
                              }

                              final bool isPinValid = await CryptoEngine.verifyPin(pinVerifyController.text, globalPin);

                              if (isPinValid) {
                                await settingsBox.put('secure_failed_attempts', 0);
                                await settingsBox.put('secure_lockout_until', 0);

                                if (!context.mounted) return;
                                Navigator.pop(context);
                                if (!screenContext.mounted) return;

                                if (openForEditing) {
                                  String rawContent = '';
                                  try {
                                    rawContent = await CryptoEngine.decryptProcess(item.content, globalPin);
                                    if (rawContent != 'DECRYPTION FAULT' && item.pendingReviewAfterSync) {
                                      // Content was swapped in from backup without decryption during
                                      // conflict resolution - it may still be in the combined
                                      // title+body format used for the GitHub payload. Strip that
                                      // back down to just the body for display/editing, and clear
                                      // the pending flag now that the real content has been seen.
                                      rawContent = _splitTitleAndBody(rawContent).body;
                                      await ref.read(localDatabaseProvider.notifier).updateItem(
                                        item.id, item.content,
                                        pendingReviewAfterSync: false,
                                      );
                                    }
                                  } catch (_) {
                                    rawContent = 'DECRYPTION FAULT';
                                  }
                                  final unpackedItem = CaptureItem(
                                    id: item.id,
                                    title: item.title,
                                    content: rawContent,
                                    type: item.type,
                                    timestamp: item.timestamp,
                                    backupEnabled: item.backupEnabled,
                                    remoteFileId: item.remoteFileId,
                                    lastSyncedTimestamp: item.lastSyncedTimestamp,
                                    pendingReviewAfterSync: item.pendingReviewAfterSync,
                                  );
                                  _navigateToEdit(screenContext, unpackedItem);
                                } else {
                                  _revealEncryptedNotePayload(item, globalPin, isDark);
                                }
                              } else {
                                int attempts = settingsBox.get('secure_failed_attempts', defaultValue: 0) + 1;
                                await settingsBox.put('secure_failed_attempts', attempts);

                                bool flagWipeConditionTriggered = attempts > 15;
                                int penaltyDurationSeconds = flagWipeConditionTriggered
                                    ? 0
                                    : CryptoEngine.lockoutSecondsForAttempt(attempts);

                                if (flagWipeConditionTriggered) {
                                  _executeWipeSequence();
                                  await settingsBox.put('secure_failed_attempts', 0);
                                  await settingsBox.put('secure_lockout_until', 0);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  showAcknowledgeDialog(context, isDark, 'SECURITY COMPLIANCE AUDIT', 'DATA PURGED PERMANENTLY.');
                                  return;
                                }

                                if (penaltyDurationSeconds > 0) {
                                  final int unlockTimestampMillis = DateTime.now().millisecondsSinceEpoch + (penaltyDurationSeconds * 1000);
                                  await settingsBox.put('secure_lockout_until', unlockTimestampMillis);
                                }

                                setDialogState(() {
                                  pinVerifyController.clear();
                                  lockStringStatus = _checkLockoutViolation(settingsBox);
                                  if (lockStringStatus == null) {
                                    hasPinFailed = true;
                                  }
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(color: theme.textMain),
                              child: Text('VERIFY', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) => countdownTimer?.cancel());
  }

  void _revealEncryptedNotePayload(CaptureItem item, String pin, bool isDark) async {
    String decryptedContent = '';
    try {
      decryptedContent = await CryptoEngine.decryptProcess(item.content, pin);
      if (decryptedContent != 'DECRYPTION FAULT' && item.pendingReviewAfterSync) {
        // Same handling as the edit-open path - strip the combined
        // title+body format back to just the body if present, and clear
        // the pending flag now that the real content has been seen.
        decryptedContent = _splitTitleAndBody(decryptedContent).body;
        await ref.read(localDatabaseProvider.notifier).updateItem(
          item.id, item.content,
          pendingReviewAfterSync: false,
        );
      }
    } catch (e) {
      decryptedContent = 'DECRYPTION FAULT';
    }

    if (!mounted) return;
    final BuildContext screenContext = context;
    final theme = SecurityUiTheme(isDark);
    final formattedDate = _formatCustomDate(item.timestamp);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: theme.dialogBg,
                border: Border.all(color: theme.borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lock_open, color: theme.textMain, size: 13),
                          const SizedBox(width: 8),
                          Text(
                            item.title.isNotEmpty ? item.title.toUpperCase() : 'UNLOCKED CRYPTO BLOCK',
                            style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                          ),
                        ],
                      ),
                      Text(
                        formattedDate,
                        style: TextStyle(color: isDark ? const Color(0xFF666666) : const Color(0xFF888888), fontSize: 9, fontFamily: 'Courier'),
                      ),
                    ],
                  ),
                  const Divider(height: 24, thickness: 0.8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        decryptedContent,
                        style: TextStyle(color: theme.textMain, fontSize: 13, height: 1.5, letterSpacing: 0.02),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          final unpackedItem = CaptureItem(
                            id: item.id,
                            title: item.title,
                            content: decryptedContent,
                            type: item.type,
                            timestamp: item.timestamp,
                            backupEnabled: item.backupEnabled,
                            remoteFileId: item.remoteFileId,
                            lastSyncedTimestamp: item.lastSyncedTimestamp,
                            pendingReviewAfterSync: item.pendingReviewAfterSync,
                          );
                          if (!screenContext.mounted) return;
                          _navigateToEdit(screenContext, unpackedItem);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.borderColor, width: 0.8),
                          ),
                          child: Text('EDIT TEXT', style: TextStyle(color: theme.textMain, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(color: theme.textMain),
                          child: Text('CLOSE RUNTIME', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, String id) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, anim1, anim2) {
        return Consumer(
          builder: (context, ref, child) {
            final isDark = ref.watch(themeProvider);
            final theme = SecurityUiTheme(isDark);
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF121212) : Colors.white,
                    border: Border.all(color: theme.borderColor, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text('PURGE THIS DATA SEGMENT?',
                            style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.02)),
                      ),
                      Container(height: 0.8, color: theme.borderColor),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                child: Text('CANCEL', style: TextStyle(color: isDark ? const Color(0xFF737373) : const Color(0xFF888888), fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                          Container(width: 0.8, height: 40, color: theme.borderColor),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                await ref.read(localDatabaseProvider.notifier).deleteItem(id);
                                if (context.mounted) Navigator.pop(context);
                                unawaited(attemptGithubSync(ref));
                              },
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                child: const Text('DELETE', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _navigateToEdit(BuildContext context, CaptureItem item) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => EditNoteScreen(item: item),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
      ),
    );
  }

  String _formatCustomDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = (dateTime.year % 100).toString().padLeft(2, '0');
    return '$day/$month/$year';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'note' || e.type == 'encrypted_note').toList();
    final theme = SecurityUiTheme(isDark);

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: const Color(0xFF5F0E0D).withOpacity(0.6),
          selectionHandleColor: const Color(0xFF420000),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('QUICK NOTES', style: TextStyle(color: theme.textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)),
                GestureDetector(
                  onTap: _refreshLabel != 'REFRESH'
                      ? null
                      : () => performRefresh(
                    ref,
                    context,
                    onPhase: (phase) {
                      if (mounted) setState(() => _refreshLabel = phase);
                    },
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: theme.textMain),
                    child: Text(
                      _refreshLabel,
                      style: TextStyle(
                        color: isDark ? Colors.black : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    style: TextStyle(color: theme.textMain, fontSize: 14, fontWeight: FontWeight.w600),
                    cursorColor: theme.textMain,
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: TextStyle(color: theme.textSub, fontWeight: FontWeight.w400),
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.only(bottom: 8),
                    ),
                  ),
                ),
                if (_titleCheckStatus != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _titleCheckStatus!,
                    style: TextStyle(
                      color: _titleCheckStatus == 'TAKEN'
                          ? const Color(0xFFEF4444)
                          : (_titleCheckStatus == 'FETCHING' ? theme.textSub : theme.textMain),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.02,
                    ),
                  ),
                ],
              ],
            ),
            Container(height: 1.0, color: const Color(0xFFa6a6a6)),
            const SizedBox(height: 8),
            TextField(
              controller: _bodyController,
              style: TextStyle(color: theme.textMain, fontSize: 13),
              maxLines: 4,
              cursorColor: theme.textMain,
              decoration: InputDecoration(
                hintText: 'Tell me your story',
                hintStyle: TextStyle(color: theme.textSub),
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        final String? globalPin = Hive.box('rocen_settings_box').get('system_crypto_pin');
                        if (globalPin == null || globalPin.isEmpty) {
                          showMissingKeyUiDialog(context, isDark);
                        } else {
                          setState(() => _isNoteLocked = !_isNoteLocked);
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(
                            _isNoteLocked ? Icons.lock : Icons.lock_open,
                            size: 14,
                            color: _isNoteLocked ? theme.textMain : theme.textSub,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ENCRYPTION',
                            style: TextStyle(
                              color: _isNoteLocked ? theme.textMain : theme.textSub,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.02,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: () async {
                        final bool githubReady = Hive.box('rocen_settings_box').get('github_access_encrypted') != null;
                        if (!githubReady) {
                          showMissingKeyUiDialog(context, isDark, message: 'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
                          return;
                        }

                        if (!_isBackupEnabled) {
                          final bool online = await hasInternetConnection();
                          if (!online) {
                            if (!context.mounted) return;
                            showAcknowledgeDialog(
                              context,
                              isDark,
                              'YOU ARE OFFLINE',
                              "CLOUD BACKUP IS UNAVAILABLE OFFLINE. SAVE YOUR NOTE LOCALLY NOW AND ENABLE BACKUP FROM NOTE SETTINGS ONCE RECONNECTED.",
                            );
                            return;
                          }
                        }

                        setState(() => _isBackupEnabled = !_isBackupEnabled);
                        _onTitleChanged();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(
                            _isBackupEnabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                            size: 14,
                            color: _isBackupEnabled ? theme.textMain : theme.textSub,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'BACKUP',
                            style: TextStyle(
                              color: _isBackupEnabled ? theme.textMain : theme.textSub,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.02,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _compileAndSaveNote,
                  child: Text('COMMIT', style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),

            Divider(color: theme.ruleBorder, height: 16, thickness: 0.8),

            Expanded(
              child: items.isEmpty
                  ? Center(
                child: Text(
                  'NO ACTIVE NOTE REGISTRIES CURRENTLY SAVED',
                  style: TextStyle(color: theme.textSub, fontSize: 11, letterSpacing: 0.05),
                ),
              )
                  : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final bool isEncrypted = item.type == 'encrypted_note';
                  final formattedDate = _formatCustomDate(item.timestamp);

                  return GestureDetector(
                    onTap: () {
                      if (isEncrypted) {
                        _promptForPinChallenge(item, isDark);
                      } else {
                        _navigateToEdit(context, item);
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: theme.ruleBorder, width: 0.8)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: isEncrypted
                                              ? Padding(
                                            padding: const EdgeInsets.only(right: 6.0),
                                            child: Icon(Icons.lock, size: 11, color: theme.textMain),
                                          )
                                              : const SizedBox.shrink(),
                                        ),
                                        TextSpan(
                                          text: item.title.isNotEmpty ? '${item.title.toUpperCase()}  ' : 'UNTITLED  ',
                                          style: TextStyle(
                                            color: theme.textMain,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.02,
                                          ),
                                        ),
                                        if (item.pendingReviewAfterSync)
                                          TextSpan(
                                            text: '-- UPDATED  ',
                                            style: TextStyle(
                                              color: theme.textMain.withOpacity(0.7),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.03,
                                            ),
                                          ),
                                        TextSpan(
                                          text: formattedDate,
                                          style: TextStyle(
                                            color: theme.textSub,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                isEncrypted
                                    ? Text(
                                  '● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ●',
                                  style: TextStyle(color: isDark ? const Color(0xFF333333) : const Color(0xFFCCCCCC), fontSize: 10, letterSpacing: 1.2),
                                )
                                    : AnimatedClampedText(
                                  text: item.content,
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF404040),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                  maxLines: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (isEncrypted) {
                                    _promptForPinChallenge(item, isDark, openForEditing: true);
                                  } else {
                                    _navigateToEdit(context, item);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(Icons.edit_outlined, color: theme.textSub, size: 18),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _showDeleteConfirmation(context, item.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(Icons.delete_outline_rounded, color: theme.textSub, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}

class AnimatedClampedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int maxLines;

  const AnimatedClampedText({
    super.key,
    required this.text,
    required this.style,
    required this.maxLines,
  });

  @override
  State<AnimatedClampedText> createState() => _AnimatedClampedTextState();
}

class _AnimatedClampedTextState extends State<AnimatedClampedText> {
  late Timer _timer;
  int _dotIndex = 0;
  final List<String> _dotFrames = ['', '.', '..', '...', '..', '.'];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 450), (timer) {
      if (mounted) {
        setState(() {
          _dotIndex = (_dotIndex + 1) % _dotFrames.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final isOverflowing = textPainter.didExceedMaxLines;

        if (!isOverflowing) {
          return Text(widget.text, style: widget.style);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: widget.maxLines,
              overflow: TextOverflow.clip,
              style: widget.style,
            ),
            Container(
              height: 20,
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                _dotFrames[_dotIndex],
                style: widget.style.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class EditNoteScreen extends ConsumerStatefulWidget {
  final CaptureItem item;

  const EditNoteScreen({super.key, required this.item});

  @override
  ConsumerState<EditNoteScreen> createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends ConsumerState<EditNoteScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _isNoteLocked = false;
  bool _isBackupEnabled = false;
  Timer? _debounceTimer;
  Timer? _titleCheckDebounce;
  String? _titleCheckStatus;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _bodyController = TextEditingController(text: widget.item.content);
    _isNoteLocked = widget.item.type == 'encrypted_note';
    _isBackupEnabled = widget.item.backupEnabled;

    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
    _titleController.addListener(_onTitleUniquenessChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleCheckDebounce?.cancel();
    _titleController.removeListener(_onTextChanged);
    _bodyController.removeListener(_onTextChanged);
    _titleController.removeListener(_onTitleUniquenessChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTitleUniquenessChanged() {
    _titleCheckDebounce?.cancel();
    final String title = _titleController.text.trim();
    final String originalTitle = widget.item.title.trim();

    if (!_isBackupEnabled || title.isEmpty || title == originalTitle) {
      if (_titleCheckStatus != null) setState(() => _titleCheckStatus = null);
      return;
    }

    setState(() => _titleCheckStatus = 'FETCHING');

    _titleCheckDebounce = Timer(const Duration(seconds: 5), () {
      _performTitleCheck(title);
    });
  }

  Future<void> _performTitleCheck(String title) async {
    // See note in the create-note screen's _performTitleCheck - remote
    // uniqueness is no longer cheaply checkable now that filenames are
    // opaque, so this is local-only.
    final bool taken = ref.read(localDatabaseProvider.notifier).titleExists(title, excludingId: widget.item.id);
    if (mounted) setState(() => _titleCheckStatus = taken ? 'TAKEN' : 'AVAILABLE');
  }

  void _onTextChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _dynamicSave();
    });
  }

  Future<void> _dynamicSave() async {
    final bool originalIsLocked = widget.item.type == 'encrypted_note';
    if (_isNoteLocked != originalIsLocked) return;

    String contentToPersist = _bodyController.text.trim();

    if (_isNoteLocked) {
      final String? pin = Hive.box('rocen_settings_box').get('system_crypto_pin');
      if (pin != null && pin.isNotEmpty) {
        contentToPersist = await CryptoEngine.encryptProcess(contentToPersist, pin);
      }
    }

    ref.read(localDatabaseProvider.notifier).updateItem(
      widget.item.id,
      contentToPersist,
      title: _titleController.text.trim(),
      backupEnabled: _isBackupEnabled,
    );
  }

  void _toggleLock() async {
    final String? globalPin = Hive.box('rocen_settings_box').get('system_crypto_pin');
    final isDark = ref.read(themeProvider);

    if (globalPin == null || globalPin.isEmpty) {
      showMissingKeyUiDialog(context, isDark);
    } else {
      setState(() {
        _isNoteLocked = !_isNoteLocked;
      });
      await _dynamicSave();
    }
  }

  void _toggleBackup() async {
    final bool githubReady = Hive.box('rocen_settings_box').get('github_access_encrypted') != null;
    final isDark = ref.read(themeProvider);

    if (!githubReady) {
      showMissingKeyUiDialog(context, isDark, message: 'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
      return;
    }

    if (!_isBackupEnabled) {
      if (_titleController.text.trim().isEmpty) {
        showAcknowledgeDialog(context, isDark, 'BACKUP REQUIRES A TITLE', 'ENTER A NOTE TITLE BEFORE ENABLING BACKUP.');
        return;
      }
      if (ref.read(localDatabaseProvider.notifier).titleExists(_titleController.text.trim(), excludingId: widget.item.id)) {
        showAcknowledgeDialog(context, isDark, 'TITLE ALREADY TAKEN', 'CHOOSE A DIFFERENT NOTE TITLE.');
        return;
      }

      final bool online = await hasInternetConnection();
      if (!online) {
        if (!context.mounted) return;
        showAcknowledgeDialog(
          context,
          isDark,
          'YOU ARE OFFLINE',
          "CLOUD BACKUP IS UNAVAILABLE OFFLINE. SAVE YOUR NOTE LOCALLY NOW AND ENABLE BACKUP FROM NOTE SETTINGS ONCE RECONNECTED..",
        );
        return;
      }
    }

    setState(() {
      _isBackupEnabled = !_isBackupEnabled;
    });
    _onTitleUniquenessChanged();
    await _dynamicSave();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final theme = SecurityUiTheme(isDark);
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: const Color(0xFF5F0E0D).withOpacity(0.6),
          selectionHandleColor: const Color(0xFF5F0E0D),
        ),
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.textMain, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('EDIT NOTE', style: TextStyle(color: theme.textMain, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
          actions: [
            IconButton(
              icon: Icon(
                _isNoteLocked ? Icons.lock : Icons.lock_open,
                color: theme.textMain,
                size: 20,
              ),
              onPressed: _toggleLock,
            ),
            IconButton(
              icon: Icon(
                _isBackupEnabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: theme.textMain,
                size: 20,
              ),
              onPressed: _toggleBackup,
            ),
            TextButton(
              onPressed: () async {
                _debounceTimer?.cancel();
                final String rawBody = _bodyController.text.trim();
                final String cleanTitle = _titleController.text.trim();
                final bool originalIsLocked = widget.item.type == 'encrypted_note';
                String contentToPersist = rawBody;
                final String? globalPin = Hive.box('rocen_settings_box').get('system_crypto_pin');

                if (_isNoteLocked) {
                  if (globalPin != null && globalPin.isNotEmpty) {
                    contentToPersist = await CryptoEngine.encryptProcess(contentToPersist, globalPin);
                  }
                }

                if (_isBackupEnabled) {
                  final isDark = ref.read(themeProvider);
                  final bool githubReady = Hive.box('rocen_settings_box').get('github_access_encrypted') != null;
                  if (!githubReady) {
                    showMissingKeyUiDialog(context, isDark, message: 'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
                    return;
                  }
                  if (cleanTitle.isEmpty) {
                    showAcknowledgeDialog(context, isDark, 'BACKUP REQUIRES A TITLE', 'ENTER A NOTE TITLE BEFORE ENABLING BACKUP.');
                    return;
                  }
                  if (ref.read(localDatabaseProvider.notifier).titleExists(cleanTitle, excludingId: widget.item.id)) {
                    showAcknowledgeDialog(context, isDark, 'TITLE ALREADY TAKEN', 'CHOOSE A DIFFERENT NOTE TITLE.');
                    return;
                  }
                }

                bool success;

                // Remote filename is a stable opaque id, decoupled from
                // title - carry the existing one forward whenever possible
                // so a lock-status change doesn't orphan the already-synced
                // remote file under a second, abandoned filename.
                final String? existingRemoteId = widget.item.remoteFileId;
                final String? remoteIdForThisSave = _isBackupEnabled
                    ? (existingRemoteId ?? DatabaseNotifier.generateRemoteFileId())
                    : null;
                final DateTime saveTimestamp = DateTime.now();

                if (_isNoteLocked == originalIsLocked) {
                  success = await ref.read(localDatabaseProvider.notifier).updateItem(
                    widget.item.id,
                    contentToPersist,
                    title: cleanTitle,
                    backupEnabled: _isBackupEnabled,
                    remoteFileId: remoteIdForThisSave,
                    timestamp: saveTimestamp,
                  );
                } else {
                  await ref.read(localDatabaseProvider.notifier).deleteItem(widget.item.id);
                  success = await ref.read(localDatabaseProvider.notifier).insertItem(
                    contentToPersist,
                    _isNoteLocked ? 'encrypted_note' : 'note',
                    title: cleanTitle,
                    backupEnabled: _isBackupEnabled,
                    remoteFileId: remoteIdForThisSave,
                    timestamp: saveTimestamp,
                  );
                }

                if (!success) return;

                if (_isBackupEnabled && remoteIdForThisSave != null) {
                  final String combined = _combineTitleAndBody(cleanTitle, rawBody);
                  final Map<String, String> backupFields = _isNoteLocked
                      ? {...CryptoEngine.splitForBackup(await CryptoEngine.encryptProcess(combined, globalPin ?? '')), 'timestamp': saveTimestamp.toIso8601String()}
                      : {'salt': '', 'nonce': '', 'cyphertext': combined, 'timestamp': saveTimestamp.toIso8601String()};

                  await attemptGithubSync(
                    ref,
                    upsert: {remoteIdForThisSave: jsonEncode(backupFields)},
                  );
                } else {
                  unawaited(attemptGithubSync(ref));
                }

                if (context.mounted) Navigator.pop(context);
              },
              child: Text('SAVE', style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        style: TextStyle(color: theme.textMain, fontSize: 16, fontWeight: FontWeight.w600),
                        cursorColor: theme.textMain,
                        decoration: InputDecoration(
                          hintText: 'Title',
                          hintStyle: TextStyle(color: theme.textSub, fontWeight: FontWeight.w400),
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_titleCheckStatus != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _titleCheckStatus!,
                        style: TextStyle(
                          color: _titleCheckStatus == 'TAKEN'
                              ? const Color(0xFFEF4444)
                              : (_titleCheckStatus == 'FETCHING' ? theme.textSub : theme.textMain),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.02,
                        ),
                      ),
                    ],
                  ],
                ),
                Container(height: 0.8, color: theme.ruleBorder, margin: const EdgeInsets.symmetric(vertical: 12)),
                Expanded(
                  child: TextField(
                    controller: _bodyController,
                    style: TextStyle(color: theme.textMain, fontSize: 14, height: 1.6),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    cursorColor: theme.textMain,
                    decoration: InputDecoration(
                      hintText: 'Note content...',
                      hintStyle: TextStyle(color: theme.textSub),
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}