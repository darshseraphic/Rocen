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

// Combines a note's title and body into one string before it's encrypted
// (or, for unlocked-but-backed-up notes, before it's pushed as-is) for
// GitHub sync specifically - this keeps the title out of the plaintext
// GitHub filename entirely, since the remote filename is now a random
// opaque id (see DatabaseNotifier.generateRemoteFileId) with zero
// relationship to the note's content. Local storage is untouched by this -
// it keeps encrypting/storing the body alone, exactly as before.
const String _kTitleBodySeparator = '\u0000\u0000ROCEN_TITLE_SPLIT\u0000\u0000';

String _combineTitleAndBody(String title, String body) =>
    '$title$_kTitleBodySeparator$body';

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

void showMissingKeyUiDialog(BuildContext context, bool isDark,
    {String? message}) {
  final theme = SecurityUiTheme(isDark);
  final String bodyMessage =
      message ?? 'SET KEY FIRST FROM SETTINGS TO USE THIS FEATURE';
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
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.05),
                ),
                const SizedBox(height: 16),
                Text(
                  bodyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 12,
                      height: 1.5,
                      letterSpacing: 0.02,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: buttonBg,
                    child: Text('ACKNOWLEDGE',
                        style: TextStyle(
                            color: buttonText,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
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

void showAcknowledgeDialog(
    BuildContext context, bool isDark, String title, String message) {
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
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.05),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 12,
                      height: 1.5,
                      letterSpacing: 0.02,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: buttonBg,
                    child: Text('ACKNOWLEDGE',
                        style: TextStyle(
                            color: buttonText,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
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

Future<bool> attemptGithubSync(
  WidgetRef ref, {
  Map<String, String>? upsert,
}) async {
  try {
    final settingsBox = Hive.box('rocen_settings_box');

    final String? globalPin = settingsBox.get('system_crypto_pin');

    final String? accessBlob = settingsBox.get('github_access_encrypted');

    if (globalPin == null || globalPin.isEmpty || accessBlob == null) {
      secureDebugLog(
        'GITHUB SYNC ABORTED: missing PIN or stored access blob',
      );
      return false;
    }

    final String? unwrappedAccessBlob = await CryptoEngine.hardwareUnwrap(
      accessBlob,
      keyAlias: CryptoEngine.githubTokenKeyAlias,
    );

    final String accessJson = await CryptoEngine.decryptProcess(
      unwrappedAccessBlob ?? accessBlob,
      globalPin,
    );

    if (accessJson == 'DECRYPTION FAULT') {
      return false;
    }

    final Map<String, dynamic> access = jsonDecode(accessJson);

    final String? token = access['token'] as String?;

    final String? repo = access['repo'] as String?;

    if (token == null || token.isEmpty || repo == null || repo.isEmpty) {
      return false;
    }

    final service = GithubBackupService(
      token: token,
      repoPath: repo,
    );

    final notifier = ref.read(localDatabaseProvider.notifier);

    final queue = await notifier.getSyncQueue();

    await service.amendSync(
      upsertFiles: upsert ?? const {},
      deleteFiles: List<String>.from(queue['deleted']),
      renameFiles: Map<String, String>.from(queue['renamed']),
    );

    await notifier.clearSyncQueue();

    secureDebugLog('GITHUB SYNC SUCCEEDED');

    return true;
  } catch (e, stackTrace) {
    secureDebugLog('GITHUB SYNC FAILED: $e');
    secureDebugLog('$stackTrace');
    return false;
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

    final String? unwrappedAccessBlob = await CryptoEngine.hardwareUnwrap(
        accessBlob,
        keyAlias: CryptoEngine.githubTokenKeyAlias);
    final String accessJson = await CryptoEngine.decryptProcess(
        unwrappedAccessBlob ?? accessBlob, globalPin);
    if (accessJson == 'DECRYPTION FAULT') {
      return 'STORED GITHUB CREDENTIALS COULD NOT BE DECRYPTED WITH THE CURRENT PASSWORD. RE-ENTER YOUR TOKEN IN GITHUB TOKEN STORE.';
    }
    final Map<String, dynamic> access = jsonDecode(accessJson);
    final String? token = access['token'] as String?;
    final String? repo = access['repo'] as String?;
    if (token == null || repo == null) {
      return 'STORED TOKEN OR REPOSITORY WAS EMPTY.';
    }

    final backedUpItems = ref
        .read(localDatabaseProvider)
        .where((item) => item.backupEnabled)
        .toList();
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
          final String? legacyName =
              await notifier.migrateLegacyRemoteFileId(item.id);
          if (legacyName != null) legacyFilesToDelete.add(legacyName);
          final CaptureItem refreshed = ref
              .read(localDatabaseProvider)
              .firstWhere((e) => e.id == item.id);
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
            fields = {
              ...CryptoEngine.splitForBackup(item.content),
              'timestamp': item.timestamp.toIso8601String()
            };
          } else {
            final String decryptedBody =
                await CryptoEngine.decryptProcess(item.content, globalPin);
            if (decryptedBody == 'DECRYPTION FAULT') {
              secureDebugLog(
                  'SKIPPING NOTE "${item.title}" - COULD NOT DECRYPT FOR RE-PACKAGING');
              continue;
            }
            final String combined =
                _combineTitleAndBody(item.title, decryptedBody);
            final String reEncrypted =
                await CryptoEngine.encryptProcess(combined, globalPin);
            fields = {
              ...CryptoEngine.splitForBackup(reEncrypted),
              'timestamp': item.timestamp.toIso8601String()
            };
          }
        } else {
          fields = {
            'salt': '',
            'nonce': '',
            'cyphertext': _combineTitleAndBody(item.title, item.content),
            'timestamp': item.timestamp.toIso8601String()
          };
        }
        upsertFiles[remoteId] = jsonEncode(fields);
        pushedItems.add((id: item.id, timestamp: item.timestamp));
      } catch (e) {
        secureDebugLog(
            'SKIPPING CORRUPTED NOTE "${item.title}" DURING PUSH: $e');
        continue;
      }
    }

    final service = GithubBackupService(token: token, repoPath: repo);
    final queue = await notifier.getSyncQueue();
    final List<String> deleteList = [
      ...List<String>.from(queue['deleted']),
      ...legacyFilesToDelete
    ];

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
        ref
            .read(localDatabaseProvider)
            .firstWhere((e) => e.id == pushed.id)
            .content,
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

class PendingRemoteNote {
  final String? localId;
  final String title;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
  final String remoteFileId;
  final String remoteType;
  final String remoteSalt;
  final String remoteNonce;
  final String remoteCyphertext;

  // true = this note does not exist locally yet, so ACCEPTANCE will ADD it.
  // false = this note already exists locally, so ACCEPTANCE will REPLACE it.
  final bool isNewRemoteNote;

  PendingRemoteNote({
    required this.localId,
    required this.title,
    required this.localTimestamp,
    required this.remoteTimestamp,
    required this.remoteFileId,
    required this.remoteType,
    required this.remoteSalt,
    required this.remoteNonce,
    required this.remoteCyphertext,
    required this.isNewRemoteNote,
  });
}

class PullResult {
  final List<PendingRemoteNote> pendingRemoteNotes;

  PullResult({
    required this.pendingRemoteNotes,
  });
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

    if (globalPin == null || accessBlob == null) {
      return null;
    }

    final String? unwrappedAccessBlob = await CryptoEngine.hardwareUnwrap(
      accessBlob,
      keyAlias: CryptoEngine.githubTokenKeyAlias,
    );

    final String accessJson = await CryptoEngine.decryptProcess(
      unwrappedAccessBlob ?? accessBlob,
      globalPin,
    );

    if (accessJson == 'DECRYPTION FAULT') {
      return null;
    }

    final Map<String, dynamic> access = jsonDecode(accessJson);

    final String? token = access['token'] as String?;

    final String? repo = access['repo'] as String?;

    if (token == null || repo == null) {
      return null;
    }

    final service = GithubBackupService(
      token: token,
      repoPath: repo,
    );

    // ------------------------------------------------------------
    // 1. DOWNLOAD ALL REMOTE FILES
    // ------------------------------------------------------------

    final List<String> filesToImport = await service.listNoteFiles();

    filesToImport.remove('device_key.json');

    final currentBackedUpItems = ref
        .read(localDatabaseProvider)
        .where((item) => item.backupEnabled)
        .toList();

    final Map<String, CaptureItem> localByRemoteId = {
      for (final item in currentBackedUpItems)
        if (item.remoteFileId != null) item.remoteFileId!: item,
    };

    // ------------------------------------------------------------
    // 2. BUILD STAGED REMOTE NOTES
    //
    // IMPORTANT:
    // There is NO insertItem()
    // There is NO updateItem()
    // There is NO deleteItem()
    //
    // during this function.
    // ------------------------------------------------------------

    final List<PendingRemoteNote> pendingRemoteNotes = [];

    for (final fileName in filesToImport) {
      try {
        final Map<String, dynamic>? data =
            await service.fetchNoteFile(fileName);

        if (data == null) {
          continue;
        }

        final String salt = (data['salt'] ?? '').toString();

        final String nonce = (data['nonce'] ?? '').toString();

        final String cyphertext = (data['cyphertext'] ?? '').toString();

        final DateTime remoteTimestamp = DateTime.tryParse(
              (data['timestamp'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final String remoteType = salt.isEmpty ? 'note' : 'encrypted_note';

        final CaptureItem? existing = localByRemoteId[fileName];

        // --------------------------------------------------------
        // CASE A: REMOTE NOTE DOES NOT EXIST LOCALLY
        //
        // We decrypt only enough to obtain the title.
        // We DO NOT insert it.
        // --------------------------------------------------------

        if (existing == null) {
          String noteTitle;

          if (salt.isEmpty) {
            final split = _splitTitleAndBody(cyphertext);

            noteTitle = split.title;
          } else {
            final String merged = CryptoEngine.mergeFromBackup(
              salt,
              nonce,
              cyphertext,
            );

            final String decryptedCombined = await CryptoEngine.decryptProcess(
              merged,
              globalPin,
            );

            if (decryptedCombined == 'DECRYPTION FAULT') {
              continue;
            }

            final split = _splitTitleAndBody(
              decryptedCombined,
            );

            noteTitle = split.title;
          }

          if (noteTitle.trim().isEmpty) {
            noteTitle = fileName.endsWith('.json')
                ? fileName.substring(
                    0,
                    fileName.length - 5,
                  )
                : fileName;
          }

          pendingRemoteNotes.add(
            PendingRemoteNote(
              localId: null,
              title: noteTitle,
              localTimestamp: DateTime.fromMillisecondsSinceEpoch(0),
              remoteTimestamp: remoteTimestamp,
              remoteFileId: fileName,
              remoteType: remoteType,
              remoteSalt: salt,
              remoteNonce: nonce,
              remoteCyphertext: cyphertext,
              isNewRemoteNote: true,
            ),
          );

          continue;
        }

        // --------------------------------------------------------
        // CASE B: REMOTE NOTE EXISTS LOCALLY
        // --------------------------------------------------------

        final DateTime? lastSynced = existing.lastSyncedTimestamp;

        // --------------------------------------------------------
        // No previous sync baseline.
        //
        // If GitHub is newer, make it a pending user choice.
        // --------------------------------------------------------

        if (lastSynced == null) {
          if (remoteTimestamp.isAfter(existing.timestamp)) {
            pendingRemoteNotes.add(
              PendingRemoteNote(
                localId: existing.id,
                title: existing.title,
                localTimestamp: existing.timestamp,
                remoteTimestamp: remoteTimestamp,
                remoteFileId: fileName,
                remoteType: remoteType,
                remoteSalt: salt,
                remoteNonce: nonce,
                remoteCyphertext: cyphertext,
                isNewRemoteNote: false,
              ),
            );
          }

          continue;
        }

        // --------------------------------------------------------
        // COMPARE LOCAL VS REMOTE AGAINST LAST COMMON SYNC POINT
        // --------------------------------------------------------

        final bool localChanged = existing.timestamp.isAfter(lastSynced);

        final bool remoteChanged = remoteTimestamp.isAfter(lastSynced);

        // Both are unchanged.
        if (!localChanged && !remoteChanged) {
          continue;
        }

        // --------------------------------------------------------
        // REMOTE CHANGED
        //
        // Whether local also changed or not, put it into the
        // selection dialog. The user decides whether the backup
        // version should replace the current local version.
        // --------------------------------------------------------

        if (remoteChanged) {
          pendingRemoteNotes.add(
            PendingRemoteNote(
              localId: existing.id,
              title: existing.title,
              localTimestamp: existing.timestamp,
              remoteTimestamp: remoteTimestamp,
              remoteFileId: fileName,
              remoteType: remoteType,
              remoteSalt: salt,
              remoteNonce: nonce,
              remoteCyphertext: cyphertext,
              isNewRemoteNote: false,
            ),
          );

          continue;
        }

        // --------------------------------------------------------
        // LOCAL CHANGED ONLY
        //
        // Do nothing here.
        // The later PUSH will send the local version to GitHub.
        // --------------------------------------------------------

        if (localChanged && !remoteChanged) {
          continue;
        }
      } catch (e) {
        secureDebugLog(
          'FAILED TO STAGE REMOTE NOTE "$fileName": $e',
        );
        continue;
      }
    }

    // ------------------------------------------------------------
    // IMPORTANT:
    //
    // DO NOT DELETE LOCAL NOTES THAT ARE MISSING FROM GITHUB.
    //
    // Pull is now staging-only.
    // No insert/update/delete occurs here.
    // ------------------------------------------------------------

    return PullResult(
      pendingRemoteNotes: pendingRemoteNotes,
    );
  } catch (e, stackTrace) {
    secureDebugLog(
      'PULL AND STAGE FAILED: $e',
    );

    secureDebugLog(
      '$stackTrace',
    );

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
  if (diff.inDays < 30)
    return '${diff.inDays} DAY${diff.inDays == 1 ? '' : 'S'} AGO';
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
  List<PendingRemoteNote> pendingRemoteNotes,
  void Function(String phase)? onPhase,
) async {
  final theme = SecurityUiTheme(isDark);
  final Set<String> selectedRemoteIds = {};

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
                      'BACKUP NOTES FOUND',
                      style: TextStyle(
                        color: theme.textMain,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.05,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'THESE NOTES WERE FOUND IN YOUR BACKUP. CHECK ANY NOTE YOU WANT TO ADD OR REPLACE. LEAVE UNCHECKED TO KEEP WHAT\'S ON THIS DEVICE.',
                      style: TextStyle(
                        color: theme.textMain,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: pendingRemoteNotes.map((c) {
                            final bool isSelected =
                                selectedRemoteIds.contains(c.remoteFileId);
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  setDialogState(() {
                                    if (isSelected) {
                                      selectedRemoteIds.remove(c.remoteFileId);
                                    } else {
                                      selectedRemoteIds.add(c.remoteFileId);
                                    }
                                  });
                                },
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 250),
                                      width: 18,
                                      height: 18,
                                      margin: const EdgeInsets.only(top: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? theme.textMain
                                            : Colors.transparent,
                                        border: Border.all(
                                            color: theme.textMain, width: 1.2),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.title.isEmpty
                                                ? '(UNTITLED)'
                                                : c.title,
                                            style: TextStyle(
                                              color: theme.textMain,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            c.isNewRemoteNote
                                                ? 'BACKUP: ${_formatTimeAgo(c.remoteTimestamp)}   ·   NEW NOTE'
                                                : 'THIS DEVICE: ${_formatTimeAgo(c.localTimestamp)}   ·   BACKUP: ${_formatTimeAgo(c.remoteTimestamp)}',
                                            style: TextStyle(
                                              color: theme.textMain
                                                  .withOpacity(0.6),
                                              fontSize: 9,
                                              letterSpacing: 0.02,
                                            ),
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
                        final notifier =
                            ref.read(localDatabaseProvider.notifier);

                        final String? globalPin = Hive.box('rocen_settings_box')
                            .get('system_crypto_pin');

                        if (globalPin == null || globalPin.isEmpty) {
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }

                          if (context.mounted) {
                            showMissingKeyUiDialog(context, isDark);
                          }

                          return;
                        }

                        for (final pending in pendingRemoteNotes) {
                          // ----------------------------------------------------------
                          // UNCHECKED:
                          // Do absolutely nothing.
                          // ----------------------------------------------------------
                          if (!selectedRemoteIds
                              .contains(pending.remoteFileId)) {
                            continue;
                          }

                          // ----------------------------------------------------------
                          // CHECKED + LOCAL NOTE DOES NOT EXIST
                          // → ADD THE REMOTE NOTE
                          // ----------------------------------------------------------
                          if (pending.isNewRemoteNote) {
                            String localReadyContent;

                            if (pending.remoteSalt.isEmpty) {
                              final split = _splitTitleAndBody(
                                pending.remoteCyphertext,
                              );

                              localReadyContent = split.body;
                            } else {
                              final String merged =
                                  CryptoEngine.mergeFromBackup(
                                pending.remoteSalt,
                                pending.remoteNonce,
                                pending.remoteCyphertext,
                              );

                              final String decryptedCombined =
                                  await CryptoEngine.decryptProcess(
                                merged,
                                globalPin,
                              );

                              if (decryptedCombined == 'DECRYPTION FAULT') {
                                continue;
                              }

                              final split =
                                  _splitTitleAndBody(decryptedCombined);

                              localReadyContent =
                                  await CryptoEngine.encryptProcess(
                                split.body,
                                globalPin,
                              );
                            }

                            await notifier.insertItem(
                              localReadyContent,
                              pending.remoteType,
                              title: pending.title,
                              backupEnabled: true,
                              remoteFileId: pending.remoteFileId,
                              timestamp: pending.remoteTimestamp,
                              lastSyncedTimestamp: pending.remoteTimestamp,
                            );

                            continue;
                          }

                          // ----------------------------------------------------------
                          // CHECKED + LOCAL NOTE EXISTS
                          // → REPLACE THE LOCAL NOTE
                          // ----------------------------------------------------------
                          if (pending.localId == null) {
                            continue;
                          }

                          await _applyRemoteSwap(
                            notifier,
                            localId: pending.localId!,
                            remoteFileId: pending.remoteFileId,
                            remoteType: pending.remoteType,
                            salt: pending.remoteSalt,
                            nonce: pending.remoteNonce,
                            cyphertext: pending.remoteCyphertext,
                            remoteTimestamp: pending.remoteTimestamp,
                          );
                        }

// Close the selection dialog after applying the user's choices.
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

// Push the resulting local state to GitHub.
                        final String? pushError =
                            await pushAllBackupEnabledNotes(ref);

// If the cloud update failed, do not report CLEAN.
                        if (pushError != null) {
                          if (context.mounted) {
                            showAcknowledgeDialog(
                              context,
                              isDark,
                              'SYNC PARTIALLY COMPLETE',
                              'GITHUB UPDATE FAILED: $pushError',
                            );
                          }

                          onPhase?.call('REFRESH');
                          return;
                        }

// Local and GitHub are now synchronized.
                        onPhase?.call('CLEAN');
                        await Future.delayed(
                          const Duration(milliseconds: 700),
                        );

                        onPhase?.call('REFRESH');
                      },
                      child: Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        color: isDark ? Colors.white : Colors.black,
                        child: Text(
                          'ACCEPTANCE',
                          style: TextStyle(
                              color: isDark ? Colors.black : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
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
  List<PendingRemoteNote>? pendingRemoteNotes;
  try {
    onPhase?.call('FETCH');

    final bool online = await hasInternetConnection();
    if (!online) {
      onPhase?.call('REFRESH');
      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'YOU ARE OFFLINE',
            'CONNECT TO THE INTERNET TO REFRESH YOUR BACKUP.');
      }
      return;
    }

    final settingsBox = Hive.box('rocen_settings_box');
    final bool configured = settingsBox.get('system_crypto_pin') != null &&
        settingsBox.get('github_access_encrypted') != null;
    if (!configured) {
      onPhase?.call('REFRESH');
      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'GITHUB NOT CONFIGURED',
            'SET UP THE GITHUB TOKEN STORE IN SETTINGS FIRST.');
      }
      return;
    }

    const int cooldownMillis = 5000;
    final int? lastCompletedAt = settingsBox.get('last_refresh_completed_at');
    if (lastCompletedAt != null) {
      final int elapsed =
          DateTime.now().millisecondsSinceEpoch - lastCompletedAt;
      if (elapsed < cooldownMillis) {
        onPhase?.call('REFRESH');
        if (!silent && context.mounted) {
          final int remainingSeconds =
              ((cooldownMillis - elapsed) / 1000).ceil();
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
      // PULL FIRST, THEN PUSH - this order matters. Pushing before pulling
      // means every refresh would blindly overwrite GitHub with this
      // device's current (possibly stale) copy of every note BEFORE ever
      // checking what changed remotely - silently clobbering a newer edit
      // from another device before pull even had a chance to see it. This
      // was a real bug: pull second saw its own just-pushed content and
      // reported "up to date" even when another device's change had
      // existed on GitHub moments earlier.
      onPhase?.call('DECRYPT');
      final PullResult? result = await pullAndReconcileNotes(ref);
      if (result == null)
        throw RefreshFailure('COULD NOT FETCH YOUR BACKUP FROM GITHUB.');

      if (result.pendingRemoteNotes.isNotEmpty) {
        pendingRemoteNotes = result.pendingRemoteNotes;

        // Tell the user that the backup contains changes
        // requiring a decision.
        onPhase?.call('SUCCESS');

        await Future.delayed(
          const Duration(milliseconds: 300),
        );

        onPhase?.call('CHANGE');

        return;
      }

      // No pending remote decisions - safe to push local-only changes...(new notes, or
      // notes edited locally where remote was untouched) now that pull has
      // already reconciled anything that came from elsewhere first.
      final String? pushError = await pushAllBackupEnabledNotes(ref);

      if (pushError != null) {
        throw RefreshFailure(pushError);
      }

// The refresh reached the backend successfully.
      onPhase?.call('SUCCESS');

      await Future.delayed(
        const Duration(milliseconds: 450),
      );

// The local database is clean and matches the resulting
// synchronized state.
      onPhase?.call('CLEAN');

      await Future.delayed(
        const Duration(milliseconds: 700),
      );

// Return the button to its normal state.
      onPhase?.call('REFRESH');
    }

    try {
      await runSync().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await settingsBox.put(
          'last_refresh_completed_at', DateTime.now().millisecondsSinceEpoch);
      onPhase?.call('REFRESH');
      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'CONNECTION TOO SLOW',
            'YOUR INTERNET CONNECTION IS SLOW. PLEASE TRY AGAIN.');
      }
      return;
    } on RefreshFailure catch (f) {
      await settingsBox.put(
          'last_refresh_completed_at', DateTime.now().millisecondsSinceEpoch);
      onPhase?.call('REFRESH');
      if (!silent && context.mounted) {
        showAcknowledgeDialog(context, isDark, 'REFRESH FAILED', f.message);
      }
      return;
    }

    await settingsBox.put(
        'last_refresh_completed_at', DateTime.now().millisecondsSinceEpoch);

    await Future.delayed(
      const Duration(milliseconds: 900),
    );

// Do NOT reset to REFRESH here.
//
// runSync() already does:
//   CLEAN → REFRESH
// for a clean sync.
//
// When changes exist, runSync() leaves the button at:
//   CHANGE
//
// That CHANGE state must remain visible while the selection dialog
// is open.

// Pending remote notes are surfaced while the button still says CHANGE.
    if (pendingRemoteNotes != null &&
        pendingRemoteNotes!.isNotEmpty &&
        context.mounted) {
      await showConflictResolutionDialog(
        context,
        ref,
        isDark,
        pendingRemoteNotes!,
        onPhase,
      );
    }
  } catch (e) {
    secureDebugLog('REFRESH UNCAUGHT EXCEPTION: $e');
    try {
      await Hive.box('rocen_settings_box').put(
          'last_refresh_completed_at', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
    onPhase?.call('REFRESH');
    if (!silent && context.mounted) {
      showAcknowledgeDialog(
          context, isDark, 'REFRESH ERROR', 'UNEXPECTED ERROR: $e');
    }
  }
}

Future<bool> hasInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('github.com')
        .timeout(const Duration(seconds: 4));
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
    final bool taken =
        ref.read(localDatabaseProvider.notifier).titleExists(title);
    if (mounted)
      setState(() => _titleCheckStatus = taken ? 'TAKEN' : 'AVAILABLE');
  }

  void _enforceKeyRotationPurge() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsBox = Hive.box('rocen_settings_box');
      final String? currentPin = settingsBox.get('system_crypto_pin');
      final String? lastActivePin =
          settingsBox.get('last_active_crypto_pin_snapshot');

      if (currentPin != lastActivePin) {
        _executeWipeSequence();
        settingsBox.put('last_active_crypto_pin_snapshot', currentPin);
      }
    });
  }

  void _executeWipeSequence() {
    final currentItems = ref.read(localDatabaseProvider);
    final targetsToPurge =
        currentItems.where((item) => item.type == 'encrypted_note').toList();

    for (var target in targetsToPurge) {
      ref.read(localDatabaseProvider.notifier).deleteItem(target.id);
    }
  }

  String? _checkLockoutViolation(Box settingsBox) {
    final int lockoutUntil =
        settingsBox.get('secure_lockout_until', defaultValue: 0);
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
    final String? globalPin =
        Hive.box('rocen_settings_box').get('system_crypto_pin');

    if (_isNoteLocked) {
      if (globalPin == null || globalPin.isEmpty) {
        showMissingKeyUiDialog(context, isDark);
        return;
      }
      finalPayload = await CryptoEngine.encryptProcess(cleanBody, globalPin);
    }

    if (_isBackupEnabled) {
      final settingsBox = Hive.box('rocen_settings_box');
      final bool githubReady =
          settingsBox.get('github_access_encrypted') != null;

      if (!githubReady) {
        showMissingKeyUiDialog(context, isDark,
            message:
                'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
        return;
      }

      if (cleanTitle.isEmpty) {
        showAcknowledgeDialog(context, isDark, 'BACKUP REQUIRES A TITLE',
            'ENTER A NOTE TITLE BEFORE ENABLING BACKUP.');
        return;
      }

      if (ref.read(localDatabaseProvider.notifier).titleExists(cleanTitle)) {
        showAcknowledgeDialog(context, isDark, 'TITLE ALREADY TAKEN',
            'CHOOSE A DIFFERENT NOTE TITLE.');
        return;
      }
    }

    final String? generatedRemoteId =
        _isBackupEnabled ? DatabaseNotifier.generateRemoteFileId() : null;
    final DateTime saveTimestamp = DateTime.now();

    // Save the current editor state in case the local insert fails.
    final String savedTitle = cleanTitle;
    final String savedBody = cleanBody;
    final bool savedLocked = _isNoteLocked;
    final bool savedBackupEnabled = _isBackupEnabled;

// Clear the editor BEFORE inserting into the database.
// This prevents the new list item from appearing while the
// old title/body are still visible in the create form.
    _titleController.clear();
    _bodyController.clear();

    setState(() {
      _isNoteLocked = false;
      _isBackupEnabled = false;
    });

    FocusScope.of(context).unfocus();

    final bool inserted =
        await ref.read(localDatabaseProvider.notifier).insertItem(
              finalPayload,
              savedLocked ? 'encrypted_note' : 'note',
              title: savedTitle,
              backupEnabled: savedBackupEnabled,
              remoteFileId: generatedRemoteId,
              timestamp: saveTimestamp,
            );

    if (!inserted) {
      // Roll back the editor if the local save failed.
      _titleController.text = savedTitle;
      _bodyController.text = savedBody;

      setState(() {
        _isNoteLocked = savedLocked;
        _isBackupEnabled = savedBackupEnabled;
      });

      return;
    }

    if (savedBackupEnabled && generatedRemoteId != null) {
      final String combined = _combineTitleAndBody(savedTitle, savedBody);

      final Map<String, String> backupFields = savedLocked
          ? {
              ...CryptoEngine.splitForBackup(
                await CryptoEngine.encryptProcess(
                  combined,
                  globalPin!,
                ),
              ),
              'timestamp': saveTimestamp.toIso8601String(),
            }
          : {
              'salt': '',
              'nonce': '',
              'cyphertext': combined,
              'timestamp': saveTimestamp.toIso8601String(),
            };

      await attemptGithubSync(
        ref,
        upsert: {
          generatedRemoteId: jsonEncode(backupFields),
        },
      );
    }

    Hive.box('rocen_settings_box')
        .put('last_active_crypto_pin_snapshot', globalPin);
  }

  void _promptForPinChallenge(CaptureItem item, bool isDark,
      {bool openForEditing = false}) {
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
            String displayHeaderTitle = 'ENTER PASSWORD';
            if (lockStringStatus != null) {
              displayHeaderTitle = lockStringStatus!;
            } else if (hasPinFailed) {
              displayHeaderTitle = 'INVALID PASSWORD - TRY AGAIN';
            }

            return Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  selectionColor: theme.textMain.withOpacity(0.2),
                  selectionHandleColor: theme.textMain,
                  cursorColor: theme.textMain,
                ),
              ),
              child: Center(
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
                        Text(displayHeaderTitle,
                            style: TextStyle(
                                color:
                                    (hasPinFailed || lockStringStatus != null)
                                        ? const Color(0xFFEF4444)
                                        : theme.textMain,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.05)),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: (hasPinFailed || lockStringStatus != null)
                                  ? const Color(0xFFEF4444)
                                  : theme.borderColor,
                              width: (hasPinFailed || lockStringStatus != null)
                                  ? 1.2
                                  : 0.8,
                            ),
                          ),
                          child: TextField(
                            controller: pinVerifyController,
                            keyboardType: TextInputType.text,
                            maxLength: 32,
                            obscureText: true,
                            obscuringCharacter: '#',
                            cursorColor: theme.textMain,
                            autofocus: lockStringStatus == null,
                            enabled: lockStringStatus == null,
                            style: TextStyle(
                              color: (hasPinFailed || lockStringStatus != null)
                                  ? const Color(0xFFEF4444)
                                  : theme.textMain,
                              fontSize: 16,
                              letterSpacing: 4,
                              fontWeight: FontWeight.bold,
                            ),
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
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            InkWell(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: theme.borderColor, width: 0.8),
                                ),
                                child: Text('CANCEL',
                                    style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFF888888)
                                            : const Color(0xFF525252),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () async {
                                final activeLockCheck =
                                    _checkLockoutViolation(settingsBox);
                                if (activeLockCheck != null) {
                                  setDialogState(() {
                                    lockStringStatus = activeLockCheck;
                                  });
                                  return;
                                }

                                final bool isPinValid =
                                    await CryptoEngine.verifyPin(
                                        pinVerifyController.text, globalPin);

                                if (isPinValid) {
                                  await settingsBox.put(
                                      'secure_failed_attempts', 0);
                                  await settingsBox.put(
                                      'secure_lockout_until', 0);

                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  if (!screenContext.mounted) return;

                                  if (openForEditing) {
                                    String rawContent = '';
                                    try {
                                      rawContent =
                                          await CryptoEngine.decryptProcess(
                                              item.content, globalPin);
                                      if (rawContent != 'DECRYPTION FAULT' &&
                                          item.pendingReviewAfterSync) {
                                        // Content was swapped in from backup without decryption during
                                        // conflict resolution - it may still be in the combined
                                        // title+body format used for the GitHub payload. Strip that
                                        // back down to just the body for display/editing, and clear
                                        // the pending flag now that the real content has been seen.
                                        rawContent =
                                            _splitTitleAndBody(rawContent).body;
                                        await ref
                                            .read(
                                                localDatabaseProvider.notifier)
                                            .updateItem(
                                              item.id,
                                              item.content,
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
                                      lastSyncedTimestamp:
                                          item.lastSyncedTimestamp,
                                      pendingReviewAfterSync:
                                          item.pendingReviewAfterSync,
                                    );
                                    _navigateToEdit(
                                        screenContext, unpackedItem);
                                  } else {
                                    _revealEncryptedNotePayload(
                                        item, globalPin, isDark);
                                  }
                                } else {
                                  int attempts = settingsBox.get(
                                          'secure_failed_attempts',
                                          defaultValue: 0) +
                                      1;
                                  await settingsBox.put(
                                      'secure_failed_attempts', attempts);

                                  bool flagWipeConditionTriggered =
                                      attempts > 15;
                                  int penaltyDurationSeconds =
                                      flagWipeConditionTriggered
                                          ? 0
                                          : CryptoEngine
                                              .lockoutSecondsForAttempt(
                                                  attempts);

                                  if (flagWipeConditionTriggered) {
                                    _executeWipeSequence();
                                    await settingsBox.put(
                                        'secure_failed_attempts', 0);
                                    await settingsBox.put(
                                        'secure_lockout_until', 0);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    showAcknowledgeDialog(
                                        context,
                                        isDark,
                                        'SECURITY COMPLIANCE AUDIT',
                                        'DATA PURGED PERMANENTLY.');
                                    return;
                                  }

                                  if (penaltyDurationSeconds > 0) {
                                    final int unlockTimestampMillis =
                                        DateTime.now().millisecondsSinceEpoch +
                                            (penaltyDurationSeconds * 1000);
                                    await settingsBox.put(
                                        'secure_lockout_until',
                                        unlockTimestampMillis);
                                  }

                                  setDialogState(() {
                                    pinVerifyController.clear();
                                    lockStringStatus =
                                        _checkLockoutViolation(settingsBox);
                                    if (lockStringStatus == null) {
                                      hasPinFailed = true;
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration:
                                    BoxDecoration(color: theme.textMain),
                                child: Text('VERIFY',
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.black
                                            : Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) => countdownTimer?.cancel());
  }

  void _revealEncryptedNotePayload(
      CaptureItem item, String pin, bool isDark) async {
    String decryptedContent = '';
    try {
      decryptedContent = await CryptoEngine.decryptProcess(item.content, pin);
      if (decryptedContent != 'DECRYPTION FAULT' &&
          item.pendingReviewAfterSync) {
        // Same handling as the edit-open path - strip the combined
        // title+body format back to just the body if present, and clear
        // the pending flag now that the real content has been seen.
        decryptedContent = _splitTitleAndBody(decryptedContent).body;
        await ref.read(localDatabaseProvider.notifier).updateItem(
              item.id,
              item.content,
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
                          Icon(Icons.lock_open,
                              color: theme.textMain, size: 13),
                          const SizedBox(width: 8),
                          Text(
                            item.title.isNotEmpty
                                ? item.title.toUpperCase()
                                : 'UNLOCKED CRYPTO BLOCK',
                            style: TextStyle(
                                color: theme.textMain,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.05),
                          ),
                        ],
                      ),
                      Text(
                        formattedDate,
                        style: TextStyle(
                            color: isDark
                                ? const Color(0xFF666666)
                                : const Color(0xFF888888),
                            fontSize: 9,
                            fontFamily: 'Courier'),
                      ),
                    ],
                  ),
                  const Divider(height: 24, thickness: 0.8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        decryptedContent,
                        style: TextStyle(
                            color: theme.textMain,
                            fontSize: 13,
                            height: 1.5,
                            letterSpacing: 0.02),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: theme.borderColor, width: 0.8),
                          ),
                          child: Text('EDIT TEXT',
                              style: TextStyle(
                                  color: theme.textMain,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(color: theme.textMain),
                          child: Text('CLOSE RUNTIME',
                              style: TextStyle(
                                  color: isDark ? Colors.black : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
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
                            style: TextStyle(
                                color: theme.textMain,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.02)),
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
                                child: Text('CANCEL',
                                    style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFF737373)
                                            : const Color(0xFF888888),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                          Container(
                              width: 0.8, height: 40, color: theme.borderColor),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                await ref
                                    .read(localDatabaseProvider.notifier)
                                    .deleteItem(id);
                                if (context.mounted) Navigator.pop(context);
                                unawaited(attemptGithubSync(ref));
                              },
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                child: const Text('DELETE',
                                    style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
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
        pageBuilder: (context, animation, secondaryAnimation) =>
            EditNoteScreen(item: item),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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
    final items = ref
        .watch(localDatabaseProvider)
        .where((e) => e.type == 'note' || e.type == 'encrypted_note')
        .toList();
    final theme = SecurityUiTheme(isDark);

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: theme.textMain.withOpacity(0.2),
          selectionHandleColor: theme.textMain,
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
                Text('QUICK NOTES',
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.02)),
                GestureDetector(
                  onTap: _refreshLabel != 'REFRESH'
                      ? null
                      : () => performRefresh(
                            ref,
                            context,
                            onPhase: (phase) {
                              if (mounted)
                                setState(() => _refreshLabel = phase);
                            },
                          ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    cursorColor: theme.textMain,
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: TextStyle(
                          color: theme.textSub, fontWeight: FontWeight.w400),
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
                          : (_titleCheckStatus == 'FETCHING'
                              ? theme.textSub
                              : theme.textMain),
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
                        final String? globalPin = Hive.box('rocen_settings_box')
                            .get('system_crypto_pin');
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
                            color:
                                _isNoteLocked ? theme.textMain : theme.textSub,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ENCRYPTION',
                            style: TextStyle(
                              color: _isNoteLocked
                                  ? theme.textMain
                                  : theme.textSub,
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
                        final bool githubReady = Hive.box('rocen_settings_box')
                                .get('github_access_encrypted') !=
                            null;
                        if (!githubReady) {
                          showMissingKeyUiDialog(context, isDark,
                              message:
                                  'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
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
                            _isBackupEnabled
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            size: 14,
                            color: _isBackupEnabled
                                ? theme.textMain
                                : theme.textSub,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'BACKUP',
                            style: TextStyle(
                              color: _isBackupEnabled
                                  ? theme.textMain
                                  : theme.textSub,
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
                  child: Text('COMMIT',
                      style: TextStyle(
                          color: theme.textMain,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Divider(color: theme.ruleBorder, height: 16, thickness: 0.8),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'NO ACTIVE NOTE REGISTRIES CURRENTLY SAVED',
                        style: TextStyle(
                            color: theme.textSub,
                            fontSize: 11,
                            letterSpacing: 0.05),
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
                              border: Border(
                                  bottom: BorderSide(
                                      color: theme.ruleBorder, width: 0.8)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: RichText(
                                          text: TextSpan(
                                            children: [
                                              WidgetSpan(
                                                alignment:
                                                    PlaceholderAlignment.middle,
                                                child: isEncrypted
                                                    ? Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                right: 6.0),
                                                        child: Icon(Icons.lock,
                                                            size: 11,
                                                            color:
                                                                theme.textMain),
                                                      )
                                                    : const SizedBox.shrink(),
                                              ),
                                              TextSpan(
                                                text: item.title.isNotEmpty
                                                    ? '${item.title.toUpperCase()}  '
                                                    : 'UNTITLED  ',
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
                                                    color: theme.textMain
                                                        .withOpacity(0.7),
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
                                              style: TextStyle(
                                                  color: isDark
                                                      ? const Color(0xFF333333)
                                                      : const Color(0xFFCCCCCC),
                                                  fontSize: 10,
                                                  letterSpacing: 1.2),
                                            )
                                          : AnimatedClampedText(
                                              text: item.content,
                                              style: TextStyle(
                                                color: isDark
                                                    ? const Color(0xFFA3A3A3)
                                                    : const Color(0xFF404040),
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
                                          _promptForPinChallenge(item, isDark,
                                              openForEditing: true);
                                        } else {
                                          _navigateToEdit(context, item);
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Icon(Icons.edit_outlined,
                                            color: theme.textSub, size: 18),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => _showDeleteConfirmation(
                                          context, item.id),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Icon(
                                            Icons.delete_outline_rounded,
                                            color: theme.textSub,
                                            size: 20),
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
    final bool taken = ref
        .read(localDatabaseProvider.notifier)
        .titleExists(title, excludingId: widget.item.id);
    if (mounted)
      setState(() => _titleCheckStatus = taken ? 'TAKEN' : 'AVAILABLE');
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
      final String? pin =
          Hive.box('rocen_settings_box').get('system_crypto_pin');
      if (pin != null && pin.isNotEmpty) {
        contentToPersist =
            await CryptoEngine.encryptProcess(contentToPersist, pin);
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
    final String? globalPin =
        Hive.box('rocen_settings_box').get('system_crypto_pin');
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
    final bool githubReady =
        Hive.box('rocen_settings_box').get('github_access_encrypted') != null;
    final isDark = ref.read(themeProvider);

    if (!githubReady) {
      showMissingKeyUiDialog(context, isDark,
          message: 'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
      return;
    }

    if (!_isBackupEnabled) {
      if (_titleController.text.trim().isEmpty) {
        showAcknowledgeDialog(context, isDark, 'BACKUP REQUIRES A TITLE',
            'ENTER A NOTE TITLE BEFORE ENABLING BACKUP.');
        return;
      }
      if (ref.read(localDatabaseProvider.notifier).titleExists(
          _titleController.text.trim(),
          excludingId: widget.item.id)) {
        showAcknowledgeDialog(context, isDark, 'TITLE ALREADY TAKEN',
            'CHOOSE A DIFFERENT NOTE TITLE.');
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
          selectionColor: theme.textMain.withOpacity(0.2),
          selectionHandleColor: theme.textMain,
        ),
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: theme.textMain, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('EDIT NOTE',
              style: TextStyle(
                  color: theme.textMain,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1)),
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
                _isBackupEnabled
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
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
                final bool originalIsLocked =
                    widget.item.type == 'encrypted_note';
                String contentToPersist = rawBody;
                final String? globalPin =
                    Hive.box('rocen_settings_box').get('system_crypto_pin');

                if (_isNoteLocked) {
                  if (globalPin != null && globalPin.isNotEmpty) {
                    contentToPersist = await CryptoEngine.encryptProcess(
                        contentToPersist, globalPin);
                  }
                }

                if (_isBackupEnabled) {
                  final isDark = ref.read(themeProvider);
                  final bool githubReady = Hive.box('rocen_settings_box')
                          .get('github_access_encrypted') !=
                      null;
                  if (!githubReady) {
                    showMissingKeyUiDialog(context, isDark,
                        message:
                            'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
                    return;
                  }
                  if (cleanTitle.isEmpty) {
                    showAcknowledgeDialog(
                        context,
                        isDark,
                        'BACKUP REQUIRES A TITLE',
                        'ENTER A NOTE TITLE BEFORE ENABLING BACKUP.');
                    return;
                  }
                  if (ref
                      .read(localDatabaseProvider.notifier)
                      .titleExists(cleanTitle, excludingId: widget.item.id)) {
                    showAcknowledgeDialog(
                        context,
                        isDark,
                        'TITLE ALREADY TAKEN',
                        'CHOOSE A DIFFERENT NOTE TITLE.');
                    return;
                  }
                }

                bool success;
                final String? existingRemoteId = widget.item.remoteFileId;
                final String? remoteIdForThisSave = _isBackupEnabled
                    ? (existingRemoteId ??
                        DatabaseNotifier.generateRemoteFileId())
                    : null;
                final DateTime saveTimestamp = DateTime.now();

                if (_isNoteLocked == originalIsLocked) {
                  success =
                      await ref.read(localDatabaseProvider.notifier).updateItem(
                            widget.item.id,
                            contentToPersist,
                            title: cleanTitle,
                            backupEnabled: _isBackupEnabled,
                            remoteFileId: remoteIdForThisSave,
                            timestamp: saveTimestamp,
                          );
                } else {
                  await ref
                      .read(localDatabaseProvider.notifier)
                      .deleteItem(widget.item.id);
                  success =
                      await ref.read(localDatabaseProvider.notifier).insertItem(
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
                  final String combined =
                      _combineTitleAndBody(cleanTitle, rawBody);

                  final Map<String, String> backupFields = _isNoteLocked
                      ? {
                          ...CryptoEngine.splitForBackup(
                              await CryptoEngine.encryptProcess(
                                  combined, globalPin ?? '')),
                          'timestamp': saveTimestamp.toIso8601String()
                        }
                      : {
                          'salt': '',
                          'nonce': '',
                          'cyphertext': combined,
                          'timestamp': saveTimestamp.toIso8601String()
                        };

                  final bool pushSucceeded = await attemptGithubSync(
                    ref,
                    upsert: {
                      remoteIdForThisSave: jsonEncode(backupFields),
                    },
                  );

                  if (pushSucceeded) {
                    await ref.read(localDatabaseProvider.notifier).updateItem(
                          widget.item.id,
                          contentToPersist,
                          timestamp: saveTimestamp,
                          lastSyncedTimestamp: saveTimestamp,
                        );
                  }
                } else {
                  unawaited(attemptGithubSync(ref));
                }

                if (context.mounted) Navigator.pop(context);
              },
              child: Text('SAVE',
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
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
                        style: TextStyle(
                            color: theme.textMain,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                        cursorColor: theme.textMain,
                        decoration: InputDecoration(
                          hintText: 'Title',
                          hintStyle: TextStyle(
                              color: theme.textSub,
                              fontWeight: FontWeight.w400),
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
                              : (_titleCheckStatus == 'FETCHING'
                                  ? theme.textSub
                                  : theme.textMain),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.02,
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                    height: 0.8,
                    color: theme.ruleBorder,
                    margin: const EdgeInsets.symmetric(vertical: 12)),
                Expanded(
                  child: TextField(
                    controller: _bodyController,
                    style: TextStyle(
                        color: theme.textMain, fontSize: 14, height: 1.6),
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
