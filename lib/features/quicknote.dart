import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/database.dart';
import '../core/crypto_engine.dart';
import '../core/github_backup_service.dart';
import '../main.dart';

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
  final String bodyMessage = message ?? 'SET KEY FIRST FROM SETTING TO USE THIS FEATURE';
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SECURITY LOCK OUTCAST',
                  style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                ),
                const SizedBox(height: 16),
                Text(
                  bodyMessage,
                  style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5, letterSpacing: 0.02, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.borderColor, width: 0.8),
                      ),
                      child: Text('ACKNOWLEDGE', style: TextStyle(color: theme.textMain, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                )
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5, letterSpacing: 0.02, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.borderColor, width: 0.8),
                      ),
                      child: Text('ACKNOWLEDGE', style: TextStyle(color: theme.textMain, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                )
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
      debugPrint('GITHUB SYNC ABORTED: missing PIN or stored access blob (globalPin null/empty: ${globalPin == null || globalPin.isEmpty}, accessBlob null: ${accessBlob == null})');
      return;
    }

    final String accessJson = await CryptoEngine.decryptProcess(accessBlob, globalPin);
    if (accessJson == 'DECRYPTION FAULT') {
      debugPrint('GITHUB SYNC ABORTED: stored access blob failed to decrypt with the current PIN');
      return;
    }
    final Map<String, dynamic> access = jsonDecode(accessJson);
    final String? token = access['token'] as String?;
    final String? repo = access['repo'] as String?;
    if (token == null || token.isEmpty || repo == null || repo.isEmpty) {
      debugPrint('GITHUB SYNC ABORTED: token or repo field empty after decrypt (token empty: ${token == null || token.isEmpty}, repo empty: ${repo == null || repo.isEmpty})');
      return;
    }

    debugPrint('GITHUB SYNC STARTING: repo="$repo" upsertKeys=${upsert?.keys.toList()}');

    final service = GithubBackupService(token: token, repoPath: repo);
    final notifier = ref.read(localDatabaseProvider.notifier);
    final queue = await notifier.getSyncQueue();
    debugPrint('GITHUB SYNC QUEUE: deleted=${queue['deleted']} renamed=${queue['renamed']}');

    await service.amendSync(
      upsertFiles: upsert ?? const {},
      deleteFiles: List<String>.from(queue['deleted']),
      renameFiles: Map<String, String>.from(queue['renamed']),
    );

    await notifier.clearSyncQueue();
    debugPrint('GITHUB SYNC SUCCEEDED');
  } catch (e, stackTrace) {
    debugPrint('GITHUB SYNC FAILED: $e');
    debugPrint('$stackTrace');
  }
}

Future<bool> isTitleTakenRemotely(String title) async {
  try {
    final settingsBox = Hive.box('rocen_settings_box');
    final String? globalPin = settingsBox.get('system_crypto_pin');
    final String? accessBlob = settingsBox.get('github_access_encrypted');
    if (globalPin == null || accessBlob == null) return false;

    final String accessJson = await CryptoEngine.decryptProcess(accessBlob, globalPin);
    if (accessJson == 'DECRYPTION FAULT') return false;

    final Map<String, dynamic> access = jsonDecode(accessJson);
    final String? token = access['token'] as String?;
    final String? repo = access['repo'] as String?;
    if (token == null || token.isEmpty || repo == null || repo.isEmpty) return false;

    final service = GithubBackupService(token: token, repoPath: repo);
    final remote = await service.fetchNoteFile(DatabaseNotifier.noteFileName(title));
    return remote != null;
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

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _bodyController = TextEditingController();
    _titleController.addListener(_onTitleChanged);
    _enforceKeyRotationPurge();
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
    if (ref.read(localDatabaseProvider.notifier).titleExists(title)) {
      if (mounted) setState(() => _titleCheckStatus = 'TAKEN');
      return;
    }

    final bool taken = await isTitleTakenRemotely(title);
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

      if (await isTitleTakenRemotely(cleanTitle)) {
        if (!context.mounted) return;
        showAcknowledgeDialog(context, isDark, 'TITLE ALREADY TAKEN', 'CHOOSE A DIFFERENT NOTE TITLE.');
        return;
      }
    }

    final bool inserted = await ref.read(localDatabaseProvider.notifier).insertItem(
      finalPayload,
      _isNoteLocked ? 'encrypted_note' : 'note',
      title: cleanTitle,
      backupEnabled: _isBackupEnabled,
    );

    if (!inserted) return;

    if (_isBackupEnabled) {
      final Map<String, String> backupFields = _isNoteLocked
          ? CryptoEngine.splitForBackup(finalPayload)
          : {'salt': '', 'nonce': '', 'cyphertext': cleanBody};

      await attemptGithubSync(
        ref,
        upsert: {DatabaseNotifier.noteFileName(cleanTitle): jsonEncode(backupFields)},
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
            String displayHeaderTitle = 'ENTER 6-CHARACTER PASSWORD';
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
                              maxLength: 6,
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
                              children: List.generate(6, (index) {
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
                                  width: 40,
                                  height: 44,
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
                      const SizedBox(height: 24),
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
          selectionHandleColor: const Color(0xFFD5F0E0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('QUICK NOTES', style: TextStyle(color: theme.textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)),
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
                      onTap: () {
                        final bool githubReady = Hive.box('rocen_settings_box').get('github_access_encrypted') != null;
                        if (!githubReady) {
                          showMissingKeyUiDialog(context, isDark, message: 'SET GITHUB TOKEN FIRST FROM SETTINGS TO USE THIS FEATURE');
                        } else {
                          setState(() => _isBackupEnabled = !_isBackupEnabled);
                          _onTitleChanged();
                        }
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
    if (ref.read(localDatabaseProvider.notifier).titleExists(title, excludingId: widget.item.id)) {
      if (mounted) setState(() => _titleCheckStatus = 'TAKEN');
      return;
    }

    final bool taken = await isTitleTakenRemotely(title);
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
                  if (cleanTitle != widget.item.title.trim() && await isTitleTakenRemotely(cleanTitle)) {
                    if (!context.mounted) return;
                    showAcknowledgeDialog(context, isDark, 'TITLE ALREADY TAKEN', 'CHOOSE A DIFFERENT NOTE TITLE.');
                    return;
                  }
                }

                bool success;
                if (_isNoteLocked == originalIsLocked) {
                  success = await ref.read(localDatabaseProvider.notifier).updateItem(
                    widget.item.id,
                    contentToPersist,
                    title: cleanTitle,
                    backupEnabled: _isBackupEnabled,
                  );
                } else {
                  await ref.read(localDatabaseProvider.notifier).deleteItem(widget.item.id);
                  success = await ref.read(localDatabaseProvider.notifier).insertItem(
                    contentToPersist,
                    _isNoteLocked ? 'encrypted_note' : 'note',
                    title: cleanTitle,
                    backupEnabled: _isBackupEnabled,
                  );
                }

                if (!success) return;

                if (_isBackupEnabled) {
                  final Map<String, String> backupFields = _isNoteLocked
                      ? CryptoEngine.splitForBackup(contentToPersist)
                      : {'salt': '', 'nonce': '', 'cyphertext': rawBody};

                  await attemptGithubSync(
                    ref,
                    upsert: {DatabaseNotifier.noteFileName(cleanTitle): jsonEncode(backupFields)},
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