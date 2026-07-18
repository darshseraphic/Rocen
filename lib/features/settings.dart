import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../core/database.dart';
import '../core/crypto_engine.dart';
import '../core/github_backup_service.dart';
import '../main.dart';

class SettingsUiTheme {
  final bool isDark;
  late final Color textMain;
  late final Color textSub;
  late final Color mainBorderColor;
  late final Color dialogBorderColor;
  late final Color dialogBg;
  late final Color containerBg;

  SettingsUiTheme(this.isDark) {
    textMain = isDark ? Colors.white : Colors.black;
    textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    mainBorderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    dialogBorderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    containerBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEEEEEE);
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const String _boxName = 'rocen_settings_box';
  static const MethodChannel _screenSecurityChannel = MethodChannel('com.darshseraphic.rocen/screen_security');

  Future<void> _setScreenshotProtection(bool enabled) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _screenSecurityChannel.invokeMethod(enabled ? 'preventScreenshotOn' : 'preventScreenshotOff');
    } catch (_) {
    }
  }

  @override
  void initState() {
    super.initState();
    _setScreenshotProtection(true);
  }

  @override
  void dispose() {
    _setScreenshotProtection(false);
    super.dispose();
  }

  Future<void> _launchWebsiteUrl() async {
    final Uri url = Uri.parse('https://rocen.lovable.app/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('System Error: Could not execute route handshake to $url');
    }
  }

  Future<void> _launchFeedbackUrl() async {
    final Uri url = Uri.parse('https://rocen.lovable.app/feedback');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('System Error: Could not execute route handshake to $url');
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

  Future<void> _purgeEncryptedNotesOnBruteForce() async {
    final currentItems = ref.read(localDatabaseProvider);
    final targetsToPurge = currentItems.where((item) => item.type == 'encrypted_note').toList();

    for (var target in targetsToPurge) {
      await ref.read(localDatabaseProvider.notifier).deleteItem(target.id);
    }
  }

  void _showStatusDialog(BuildContext context, String title, String message) {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

    final buttonBg = isDark ? Colors.white : Colors.black;
    final buttonText = isDark ? Colors.black : Colors.white;

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
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.dialogBg,
                border: Border.all(color: theme.dialogBorderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.textMain, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.textMain, fontSize: 11, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(color: buttonBg),
                      alignment: Alignment.center,
                      child: Text(
                        'APPRECIATED',
                        style: TextStyle(
                          color: buttonText,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.06,
                        ),
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
  }

  Future<void> _pushFullBackupSync() async {
    try {
      final settingsBox = Hive.box(_boxName);
      final String? globalPin = settingsBox.get('system_crypto_pin');
      final String? accessBlob = settingsBox.get('github_access_encrypted');
      if (globalPin == null || accessBlob == null) return;

      final String accessJson = await CryptoEngine.decryptProcess(accessBlob, globalPin);
      if (accessJson == 'DECRYPTION FAULT') return;
      final Map<String, dynamic> access = jsonDecode(accessJson);
      final String? token = access['token'] as String?;
      final String? repo = access['repo'] as String?;
      if (token == null || repo == null) return;

      final backedUpItems = ref.read(localDatabaseProvider).where((item) => item.backupEnabled).toList();
      if (backedUpItems.isEmpty) return;

      final Map<String, String> upsertFiles = {};
      for (final item in backedUpItems) {
        final Map<String, String> fields;
        if (item.type == 'encrypted_note') {
          fields = CryptoEngine.splitForBackup(item.content);
        } else {
          fields = {'salt': '', 'nonce': '', 'cyphertext': item.content};
        }
        upsertFiles[DatabaseNotifier.noteFileName(item.title)] = jsonEncode(fields);
      }

      final service = GithubBackupService(token: token, repoPath: repo);
      final notifier = ref.read(localDatabaseProvider.notifier);
      final queue = await notifier.getSyncQueue();

      await service.amendSync(
        upsertFiles: upsertFiles,
        deleteFiles: List<String>.from(queue['deleted']),
        renameFiles: Map<String, String>.from(queue['renamed']),
        message: 'full export sync',
      );

      await notifier.clearSyncQueue();
    } catch (_) {
    }
  }

  Future<void> _handleDataExport() async {
    unawaited(_pushFullBackupSync());

    try {
      final String serializedJson = ref.read(localDatabaseProvider.notifier).exportToSchemaJson();
      final String timestamp = DateTime.now().toString().split(' ').first.replaceAll('-', '_');
      final String fileName = 'ROCEN_WORKSPACE_BACKUP_$timestamp.json';

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'SAVE BACKUP FILE',
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(serializedJson)),
      );

      if (outputPath != null && mounted) {
        _showStatusDialog(
          context,
          'EXPORT SUCCESSFUL',
          'YOUR LOCAL WORKSPACE SCHEMA HAS BEEN SERIALIZED AND RECORDED SAFELY TO DISK DESTINATION PATH.',
        );
      }
    } catch (e) {
      if (mounted) {
        _showStatusDialog(context, 'EXPORT FAIL', 'CRITICAL ERROR INITIALIZING SEQUENCE: ${e.toString()}');
      }
    }
  }

  Future<void> _handleDataImport() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result == null || result.files.single.path == null) return;

      final File pickedFile = File(result.files.single.path!);
      final String fileContents = await pickedFile.readAsString();

      final bool isSuccess = await ref.read(localDatabaseProvider.notifier).importFromSchemaJson(fileContents);

      if (mounted) {
        if (isSuccess) {
          _showStatusDialog(
            context,
            'RESTORE SUCCESSFUL',
            'DATABASE TRANSACTION COMPLETE. ALL WORKSPACE CACHE HAS BEEN SUCCESSFULLY RESTORED AND LOADED INTO REACTIVE SYSTEM CONTEXT.',
          );
        } else {
          _showStatusDialog(
            context,
            'RESTORE ERROR',
            'THE SELECTION PROVIDED FAILED VALIDATION CHECKS due to corrupt encoding OR STRUCTURAL COMPOSITION MISMATCH.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showStatusDialog(context, 'IMPORT FAIL', 'PROCESS ABORTED DUE TO ENCODING EXCEPTIONS: ${e.toString()}');
      }
    }
  }

  void _showRestoreChooserDialog(BuildContext context) {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

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
              width: 310,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.dialogBg,
                border: Border.all(color: theme.dialogBorderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WHICH IMPORT WOULD YOU LIKE TO RESTORE?',
                    style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5, fontWeight: FontWeight.w600, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _promptRestoreGithubChallenge(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
                            alignment: Alignment.center,
                            child: Text('GITHUB', style: TextStyle(color: theme.textMain, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.02)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _showImportWarningDialog(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
                            alignment: Alignment.center,
                            child: Text('LOCAL', style: TextStyle(color: theme.textMain, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.02)),
                          ),
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

  void _promptRestoreGithubChallenge(BuildContext context) {
    final BuildContext screenContext = context;
    final settingsBox = Hive.box(_boxName);
    final String? globalPin = settingsBox.get('system_crypto_pin');
    final String? accessBlob = settingsBox.get('github_access_encrypted');

    if (globalPin == null || globalPin.isEmpty || accessBlob == null) {
      _showStatusDialog(context, 'GITHUB NOT CONFIGURED', 'SET UP THE GITHUB TOKEN STORE FIRST BEFORE RESTORING FROM GITHUB.');
      return;
    }

    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
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
        if (current == null) timer.cancel();
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
                    border: Border.all(color: theme.dialogBorderColor, width: 0.8),
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
                          letterSpacing: 0.05,
                        ),
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
                                  if (hasPinFailed) hasPinFailed = false;
                                });
                              },
                              decoration: const InputDecoration(counterText: '', border: InputBorder.none),
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
                                  currentBoxBorderColor = isFilled ? theme.textMain.withOpacity(0.6) : theme.dialogBorderColor;
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
                              decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
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
                                final String rawPassword = pinVerifyController.text;
                                await settingsBox.put('secure_failed_attempts', 0);
                                await settingsBox.put('secure_lockout_until', 0);

                                if (!context.mounted) return;
                                Navigator.pop(context);
                                if (!screenContext.mounted) return;

                                try {
                                  final String accessJson = await CryptoEngine.decryptProcess(accessBlob, globalPin);
                                  if (accessJson == 'DECRYPTION FAULT') return;
                                  final Map<String, dynamic> access = jsonDecode(accessJson);
                                  final String? token = access['token'] as String?;
                                  final String? repo = access['repo'] as String?;
                                  if (token == null || repo == null) return;

                                  if (!screenContext.mounted) return;
                                  await _handlePostSaveGithubSync(screenContext, token, repo, rawPassword, globalPin);
                                } catch (_) {
                                }
                              } else {
                                int attempts = settingsBox.get('secure_failed_attempts', defaultValue: 0) + 1;
                                await settingsBox.put('secure_failed_attempts', attempts);

                                bool flagWipeConditionTriggered = attempts > 15;
                                int penaltyDurationSeconds = flagWipeConditionTriggered
                                    ? 0
                                    : CryptoEngine.lockoutSecondsForAttempt(attempts);

                                if (flagWipeConditionTriggered) {
                                  await _purgeEncryptedNotesOnBruteForce();
                                  await settingsBox.put('secure_failed_attempts', 0);
                                  await settingsBox.put('secure_lockout_until', 0);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  if (!screenContext.mounted) return;
                                  ScaffoldMessenger.of(screenContext).showSnackBar(
                                    const SnackBar(content: Text('SECURITY COMPLIANCE AUDIT: DATA PURGED PERMANENTLY.')),
                                  );
                                  return;
                                }

                                if (penaltyDurationSeconds > 0) {
                                  final int unlockTimestampMillis = DateTime.now().millisecondsSinceEpoch + (penaltyDurationSeconds * 1000);
                                  await settingsBox.put('secure_lockout_until', unlockTimestampMillis);
                                }

                                setDialogState(() {
                                  pinVerifyController.clear();
                                  lockStringStatus = _checkLockoutViolation(settingsBox);
                                  if (lockStringStatus == null) hasPinFailed = true;
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
                      ),
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

  void _showImportWarningDialog(BuildContext context) {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 310,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.dialogBg,
                border: Border.all(color: theme.dialogBorderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OVERWRITE CURRENT DATA',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'RESTORING WILL PERMANENTLY WIPE ALL LOGGED RECORDS FROM RECENT SESSIONS AND REPLACE THEM WITH THE SELECTED BACKUP MATRIX. THIS CANNOT BE UNDONE.',
                    style: TextStyle(color: theme.textMain, fontSize: 11.5, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                          ),
                          child: Text(
                            'CANCEL',
                            style: TextStyle(
                              color: isDark ? const Color(0xFF888888) : const Color(0xFF525252),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          _handleDataImport();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          decoration: const BoxDecoration(color: Color(0xFFEF4444)),
                          child: const Text(
                            'RESTORE DATA',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
  }

  void _showCreatePinDialog(BuildContext context, {String initialValue = ''}) {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

    final TextEditingController pinController = TextEditingController(text: initialValue);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.dialogBg,
                    border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SETUP CRYPTOGRAPHY PASSWORD',
                        style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                      ),
                      const SizedBox(height: 20),

                      Stack(
                        children: [
                          Opacity(
                            opacity: 0.0,
                            child: TextField(
                              controller: pinController,
                              keyboardType: TextInputType.text,
                              maxLength: 6,
                              autofocus: true,
                              onChanged: (val) => setDialogState(() {}),
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
                                final String text = pinController.text;
                                bool isFilled = text.length > index;
                                bool isCurrentFocus = text.length == index;

                                Color currentBoxBorderColor = isCurrentFocus
                                    ? theme.textMain
                                    : (isFilled ? theme.textMain.withOpacity(0.6) : theme.dialogBorderColor);

                                return Container(
                                  width: 40,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(
                                      color: currentBoxBorderColor,
                                      width: isCurrentFocus ? 1.2 : 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    isFilled ? '●' : '',
                                    style: TextStyle(color: theme.textMain, fontSize: 10),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Builder(builder: (context) {
                        final missing = CryptoEngine.missingPasswordRequirements(pinController.text);
                        return Text(
                          missing.isEmpty ? '' : 'MISSING: ${missing.join(', ')}',
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.02,
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                              ),
                              child: Text(
                                'CANCEL',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF888888) : const Color(0xFF525252),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: !CryptoEngine.isPasswordComplexityValid(pinController.text)
                                ? null
                                : () {
                              final typedPin = pinController.text;
                              Navigator.pop(context);
                              _showAreYouSureDialog(context, typedPin);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: CryptoEngine.isPasswordComplexityValid(pinController.text) ? theme.textMain : theme.textMain.withOpacity(0.2),
                              ),
                              child: Text(
                                'CONFIRM',
                                style: TextStyle(
                                  color: isDark ? Colors.black : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
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

  void _showAreYouSureDialog(BuildContext context, String typedPin) {
    final BuildContext screenContext = context;
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 290,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.dialogBg,
                border: Border.all(color: theme.dialogBorderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SECURITY VERIFICATION',
                    style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ARE YOU SURE TO ADD THIS PASSWORD?',
                    style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          _showCreatePinDialog(context, initialValue: typedPin);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                          ),
                          child: Text(
                            'CANCEL',
                            style: TextStyle(
                              color: isDark ? const Color(0xFF888888) : const Color(0xFF525252),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          Navigator.pop(context);

                          final securePinHash = await CryptoEngine.hashPin(typedPin);

                          final settingsBox = Hive.box(_boxName);
                          await settingsBox.put('system_crypto_pin', securePinHash);
                          await settingsBox.put('last_active_crypto_pin_snapshot', securePinHash);

                          if (screenContext.mounted) {
                            _showForgotWarningDialog(screenContext);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: theme.textMain),
                          child: Text(
                            'CONFIRM',
                            style: TextStyle(
                              color: isDark ? Colors.black : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
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
  }

  void _showForgotWarningDialog(BuildContext context) {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.dialogBg,
                border: Border.all(color: theme.dialogBorderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CRITICAL NOTICE',
                    style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'IF YOU FORGOT THE PASSWORD YOU HAVE TO TAP THE CLEAR',
                    style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(color: theme.textMain),
                        child: Text(
                          'ACKNOWLEDGE',
                          style: TextStyle(
                            color: isDark ? Colors.black : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

  void _promptChangePasswordChallenge(BuildContext context) {
    final BuildContext screenContext = context;
    final settingsBox = Hive.box(_boxName);
    final String? globalPin = settingsBox.get('system_crypto_pin');
    if (globalPin == null || globalPin.isEmpty) return;

    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
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
        if (current == null) timer.cancel();
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
            String displayHeaderTitle = 'ENTER CURRENT PASSWORD';
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
                    border: Border.all(color: theme.dialogBorderColor, width: 0.8),
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
                          letterSpacing: 0.05,
                        ),
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
                                  if (hasPinFailed) hasPinFailed = false;
                                });
                              },
                              decoration: const InputDecoration(counterText: '', border: InputBorder.none),
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
                                  currentBoxBorderColor = isFilled ? theme.textMain.withOpacity(0.6) : theme.dialogBorderColor;
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
                              decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
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
                                final String rawOldPassword = pinVerifyController.text;
                                await settingsBox.put('secure_failed_attempts', 0);
                                await settingsBox.put('secure_lockout_until', 0);

                                if (!context.mounted) return;
                                Navigator.pop(context);
                                if (!screenContext.mounted) return;
                                _showNewPasswordDialog(screenContext, globalPin, rawOldPassword);
                              } else {
                                int attempts = settingsBox.get('secure_failed_attempts', defaultValue: 0) + 1;
                                await settingsBox.put('secure_failed_attempts', attempts);

                                bool flagWipeConditionTriggered = attempts > 15;
                                int penaltyDurationSeconds = flagWipeConditionTriggered
                                    ? 0
                                    : CryptoEngine.lockoutSecondsForAttempt(attempts);

                                if (flagWipeConditionTriggered) {
                                  await _purgeEncryptedNotesOnBruteForce();
                                  await settingsBox.put('secure_failed_attempts', 0);
                                  await settingsBox.put('secure_lockout_until', 0);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  if (!screenContext.mounted) return;
                                  ScaffoldMessenger.of(screenContext).showSnackBar(
                                    const SnackBar(content: Text('SECURITY COMPLIANCE AUDIT: DATA PURGED PERMANENTLY.')),
                                  );
                                  return;
                                }

                                if (penaltyDurationSeconds > 0) {
                                  final int unlockTimestampMillis = DateTime.now().millisecondsSinceEpoch + (penaltyDurationSeconds * 1000);
                                  await settingsBox.put('secure_lockout_until', unlockTimestampMillis);
                                }

                                setDialogState(() {
                                  pinVerifyController.clear();
                                  lockStringStatus = _checkLockoutViolation(settingsBox);
                                  if (lockStringStatus == null) hasPinFailed = true;
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
                      ),
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

  void _showNewPasswordDialog(BuildContext context, String oldPinHash, String rawOldPassword) {
    final BuildContext screenContext = context;
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    final TextEditingController pinController = TextEditingController();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.dialogBg,
                    border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ENTER NEW PASSWORD', style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05)),
                      const SizedBox(height: 20),
                      Stack(
                        children: [
                          Opacity(
                            opacity: 0.0,
                            child: TextField(
                              controller: pinController,
                              keyboardType: TextInputType.text,
                              maxLength: 6,
                              autofocus: true,
                              onChanged: (val) => setDialogState(() {}),
                              decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                            ),
                          ),
                          IgnorePointer(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(6, (index) {
                                final String text = pinController.text;
                                bool isFilled = text.length > index;
                                bool isCurrentFocus = text.length == index;

                                Color currentBoxBorderColor = isCurrentFocus
                                    ? theme.textMain
                                    : (isFilled ? theme.textMain.withOpacity(0.6) : theme.dialogBorderColor);

                                return Container(
                                  width: 40,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(color: currentBoxBorderColor, width: isCurrentFocus ? 1.2 : 0.8),
                                  ),
                                  child: Text(isFilled ? '●' : '', style: TextStyle(color: theme.textMain, fontSize: 10)),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Builder(builder: (context) {
                        final missing = CryptoEngine.missingPasswordRequirements(pinController.text);
                        return Text(
                          missing.isEmpty ? '' : 'MISSING: ${missing.join(', ')}',
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 0.02),
                        );
                      }),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
                              child: Text('CANCEL', style: TextStyle(color: isDark ? const Color(0xFF888888) : const Color(0xFF525252), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: !CryptoEngine.isPasswordComplexityValid(pinController.text)
                                ? null
                                : () async {
                              final String newPassword = pinController.text;
                              Navigator.pop(context);
                              if (!screenContext.mounted) return;
                              await _executePasswordChange(screenContext, oldPinHash, rawOldPassword, newPassword);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: CryptoEngine.isPasswordComplexityValid(pinController.text) ? theme.textMain : theme.textMain.withOpacity(0.2),
                              ),
                              child: Text('CONFIRM', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
      },
    );
  }

  Future<void> _executePasswordChange(BuildContext context, String oldPinHash, String rawOldPassword, String newPassword) async {
    final settingsBox = Hive.box(_boxName);

    final currentItems = ref.read(localDatabaseProvider);
    final targetsToPurge = currentItems.where((item) => item.type == 'encrypted_note').toList();
    for (var target in targetsToPurge) {
      await ref.read(localDatabaseProvider.notifier).deleteItem(target.id);
    }

    final Uint8List authSalt = CryptoEngine.extractAuthSalt(oldPinHash);
    final String newPinHash = await CryptoEngine.hashPinWithSalt(newPassword, authSalt);

    await settingsBox.put('system_crypto_pin', newPinHash);
    await settingsBox.put('last_active_crypto_pin_snapshot', newPinHash);

    final String? accessBlob = settingsBox.get('github_access_encrypted');
    if (accessBlob != null) {
      try {
        final String accessJson = await CryptoEngine.decryptProcess(accessBlob, oldPinHash);
        if (accessJson != 'DECRYPTION FAULT') {
          final Map<String, dynamic> access = jsonDecode(accessJson);
          final String reEncrypted = await CryptoEngine.encryptProcess(accessJson, newPinHash);
          await settingsBox.put('github_access_encrypted', reEncrypted);

          if (!context.mounted) return;
          final List<String>? mnemonicWords = await _promptMnemonicRecovery(context);
          if (mnemonicWords != null) {
            final Map<String, String> rewrapped = await CryptoEngine.wrapDeviceKey(
              authSaltBytes: authSalt,
              password: newPassword,
              mnemonicWords: mnemonicWords,
            );

            try {
              final service = GithubBackupService(token: access['token'], repoPath: access['repo']);
              await service.amendSync(upsertFiles: {'device_key.json': jsonEncode(rewrapped)}, message: 'password rotation');
            } catch (_) {
            }
          }
        }
      } catch (_) {
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PASSWORD UPDATED')),
      );
    }
  }

  void _showClearConfirmationDialog(BuildContext context) {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 310,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.dialogBg,
                border: Border.all(color: theme.dialogBorderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SYSTEM DESTRUCTION WARN',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'THIS PROCESS IN NOT REVERSABLE, ALL ENCRYPTED FILE WILL REMOVED',
                    style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                          ),
                          child: Text(
                            'NO',
                            style: TextStyle(
                              color: isDark ? const Color(0xFF888888) : const Color(0xFF525252),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          Navigator.pop(context);

                          final currentItems = ref.read(localDatabaseProvider);
                          final targetsToPurge = currentItems.where((item) => item.type == 'encrypted_note').toList();

                          for (var target in targetsToPurge) {
                            await ref.read(localDatabaseProvider.notifier).deleteItem(target.id);
                          }

                          final settingsBox = Hive.box(_boxName);
                          await settingsBox.delete('system_crypto_pin');
                          await settingsBox.delete('last_active_crypto_pin_snapshot');
                          await settingsBox.delete('github_access_encrypted');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          decoration: const BoxDecoration(color: Color(0xFFEF4444)),
                          child: const Text(
                            'YES',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
  }

  void _promptGithubAccessChallenge(BuildContext context) {
    final BuildContext screenContext = context;
    final settingsBox = Hive.box(_boxName);
    final String? globalPin = settingsBox.get('system_crypto_pin');

    if (globalPin == null || globalPin.isEmpty) {
      _showStatusDialog(context, 'PASSWORD REQUIRED', 'SET THE CRYPTOGRAPHY ACCESS PASSWORD FIRST BEFORE STORING A GITHUB TOKEN.');
      return;
    }

    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
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
                    border: Border.all(color: theme.dialogBorderColor, width: 0.8),
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
                          letterSpacing: 0.05,
                        ),
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
                                  if (hasPinFailed) hasPinFailed = false;
                                });
                              },
                              decoration: const InputDecoration(counterText: '', border: InputBorder.none),
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
                                  currentBoxBorderColor = isFilled ? theme.textMain.withOpacity(0.6) : theme.dialogBorderColor;
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
                              decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
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
                                final String rawPassword = pinVerifyController.text;
                                await settingsBox.put('secure_failed_attempts', 0);
                                await settingsBox.put('secure_lockout_until', 0);

                                if (!context.mounted) return;
                                Navigator.pop(context);
                                if (!screenContext.mounted) return;
                                await _openGithubAccessDialog(screenContext, globalPin, rawPassword);
                              } else {
                                int attempts = settingsBox.get('secure_failed_attempts', defaultValue: 0) + 1;
                                await settingsBox.put('secure_failed_attempts', attempts);

                                bool flagWipeConditionTriggered = attempts > 15;
                                int penaltyDurationSeconds = flagWipeConditionTriggered
                                    ? 0
                                    : CryptoEngine.lockoutSecondsForAttempt(attempts);

                                if (flagWipeConditionTriggered) {
                                  await _purgeEncryptedNotesOnBruteForce();
                                  await settingsBox.put('secure_failed_attempts', 0);
                                  await settingsBox.put('secure_lockout_until', 0);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  if (!screenContext.mounted) return;
                                  ScaffoldMessenger.of(screenContext).showSnackBar(
                                    const SnackBar(content: Text('SECURITY COMPLIANCE AUDIT: DATA PURGED PERMANENTLY.')),
                                  );
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
                      ),
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

  Future<void> _openGithubAccessDialog(BuildContext context, String pinHash, String rawPassword) async {
    final settingsBox = Hive.box(_boxName);
    final String? accessBlob = settingsBox.get('github_access_encrypted');

    String initialToken = '';
    String initialRepo = '';

    if (accessBlob != null) {
      try {
        final String decoded = await CryptoEngine.decryptProcess(accessBlob, pinHash);
        final Map<String, dynamic> access = jsonDecode(decoded);
        initialToken = (access['token'] ?? '').toString();
        initialRepo = (access['repo'] ?? '').toString();
      } catch (_) {
      }
    }

    if (!context.mounted) return;
    _showGithubAccessDialog(context, pinHash, rawPassword, initialToken: initialToken, initialRepo: initialRepo);
  }

  void _showGithubAccessDialog(BuildContext context, String pinHash, String rawPassword, {String initialToken = '', String initialRepo = ''}) {
    final BuildContext screenContext = context;
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    final settingsBox = Hive.box(_boxName);

    final TextEditingController tokenController = TextEditingController(text: initialToken);
    final TextEditingController repoController = TextEditingController(text: initialRepo);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return Theme(
          data: Theme.of(context).copyWith(
            textSelectionTheme: const TextSelectionThemeData(
              selectionColor: Color(0x335F0E0D),
              selectionHandleColor: Color(0xFF5F0E0D),
              cursorColor: Color(0xFF5F0E0D),
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
                  border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GITHUB TOKEN STORE',
                      style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: tokenController,
                      obscureText: true,
                      contextMenuBuilder: (context, state) => const SizedBox.shrink(),
                      style: TextStyle(color: theme.textMain, fontSize: 13),
                      cursorColor: theme.textMain,
                      decoration: InputDecoration(
                        hintText: 'Fine-grained token',
                        hintStyle: TextStyle(color: theme.textSub),
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                    Container(height: 0.8, color: theme.dialogBorderColor),
                    const SizedBox(height: 16),
                    TextField(
                      controller: repoController,
                      contextMenuBuilder: (context, state) => const SizedBox.shrink(),
                      style: TextStyle(color: theme.textMain, fontSize: 13),
                      cursorColor: theme.textMain,
                      decoration: InputDecoration(
                        hintText: 'Repository (username/repo)',
                        hintStyle: TextStyle(color: theme.textSub),
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                    Container(height: 0.8, color: theme.dialogBorderColor),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
                            child: Text('CANCEL', style: TextStyle(color: isDark ? const Color(0xFF888888) : const Color(0xFF525252), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () async {
                            final String token = tokenController.text.trim();
                            final String repo = repoController.text.trim();
                            debugPrint('TOKEN DIALOG CONFIRM: tapped, token empty=${token.isEmpty}, repo="$repo"');

                            if (token.isEmpty || repo.isEmpty) {
                              debugPrint('TOKEN DIALOG CONFIRM: token or repo empty, aborting');
                              Navigator.pop(context);
                              return;
                            }

                            final String payload = jsonEncode({'token': token, 'repo': repo});
                            final String encrypted = await CryptoEngine.encryptProcess(payload, pinHash);
                            await settingsBox.put('github_access_encrypted', encrypted);
                            debugPrint('TOKEN DIALOG CONFIRM: credentials stored locally');

                            if (!context.mounted) {
                              debugPrint('TOKEN DIALOG CONFIRM: dialog context unmounted before pop, aborting');
                              return;
                            }
                            Navigator.pop(context);

                            if (!screenContext.mounted) {
                              debugPrint('TOKEN DIALOG CONFIRM: screenContext unmounted after pop, aborting sync call');
                              return;
                            }
                            debugPrint('TOKEN DIALOG CONFIRM: calling _handlePostSaveGithubSync now');
                            await _handlePostSaveGithubSync(screenContext, token, repo, rawPassword, pinHash);
                            debugPrint('TOKEN DIALOG CONFIRM: _handlePostSaveGithubSync returned');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: theme.textMain),
                            child: Text('CONFIRM', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePostSaveGithubSync(
      BuildContext context,
      String token,
      String repo,
      String rawPassword,
      String currentPinHash,
      ) async {
    debugPrint('POST-SAVE SYNC: starting, repo="$repo"');
    final service = GithubBackupService(token: token, repoPath: repo);
    final settingsBox = Hive.box(_boxName);

    Map<String, dynamic>? existingDeviceKey;
    try {
      existingDeviceKey = await service.fetchNoteFile('device_key.json');
      debugPrint('POST-SAVE SYNC: device_key.json fetch result: ${existingDeviceKey == null ? "NOT FOUND" : "FOUND"}');
    } catch (e) {
      debugPrint('POST-SAVE SYNC: device_key.json fetch THREW: $e');
      existingDeviceKey = null;
    }

    List<String> filesToImport = [];
    try {
      filesToImport = await service.listNoteFiles();
      debugPrint('POST-SAVE SYNC: listNoteFiles returned: $filesToImport');
    } catch (e) {
      debugPrint('POST-SAVE SYNC: listNoteFiles THREW: $e');
      filesToImport = [];
    }
    filesToImport.remove('device_key.json');

    String effectivePinHash = currentPinHash;

    if (existingDeviceKey == null) {
      debugPrint('POST-SAVE SYNC: taking FIRST-TIME SETUP branch (generate mnemonic + push device_key.json)');
      final Uint8List authSalt = CryptoEngine.extractAuthSalt(currentPinHash);
      final List<String> mnemonicWords = await CryptoEngine.generateMnemonic();
      debugPrint('POST-SAVE SYNC: mnemonic generated (${mnemonicWords.length} words)');
      final Map<String, String> wrapped = await CryptoEngine.wrapDeviceKey(
        authSaltBytes: authSalt,
        password: rawPassword,
        mnemonicWords: mnemonicWords,
      );
      debugPrint('POST-SAVE SYNC: device key wrapped, attempting push');

      try {
        await service.amendSync(
          upsertFiles: {'device_key.json': jsonEncode(wrapped)},
          message: 'device key setup',
        );
        debugPrint('POST-SAVE SYNC: device_key.json PUSH SUCCEEDED');
      } catch (e) {
        debugPrint('POST-SAVE SYNC: device_key.json PUSH FAILED: $e');
      }

      debugPrint('POST-SAVE SYNC: context.mounted = ${context.mounted}, about to show mnemonic dialog');
      if (context.mounted) {
        await _showMnemonicDisplayDialog(context, mnemonicWords);
        debugPrint('POST-SAVE SYNC: mnemonic dialog closed');
      } else {
        debugPrint('POST-SAVE SYNC: SKIPPED mnemonic dialog because context was unmounted');
      }
    } else if (filesToImport.isNotEmpty) {
      debugPrint('POST-SAVE SYNC: device_key.json already exists, probing same-device match');
      bool sameDeviceKey = false;
      try {
        final Map<String, dynamic>? probe = await service.fetchNoteFile(filesToImport.first);
        if (probe != null) {
          final String salt = (probe['salt'] ?? '').toString();
          final String nonce = (probe['nonce'] ?? '').toString();
          final String cyphertext = (probe['cyphertext'] ?? '').toString();

          final String testResult = salt.isEmpty
              ? cyphertext
              : await CryptoEngine.decryptProcess(
            CryptoEngine.mergeFromBackup(salt, nonce, cyphertext),
            currentPinHash,
          );
          sameDeviceKey = testResult != 'DECRYPTION FAULT';
        }
      } catch (e) {
        debugPrint('POST-SAVE SYNC: same-device probe THREW: $e');
        sameDeviceKey = false;
      }
      debugPrint('POST-SAVE SYNC: sameDeviceKey = $sameDeviceKey');

      if (!sameDeviceKey) {
        if (!context.mounted) return;
        final List<String>? recoveredWords = await _promptMnemonicRecovery(context);
        if (recoveredWords == null) return;

        final Uint8List? unwrapped = await CryptoEngine.unwrapDeviceKey(
          wrapSalt: (existingDeviceKey['wrapSalt'] ?? '').toString(),
          wrapNonce: (existingDeviceKey['wrapNonce'] ?? '').toString(),
          wrappedAuthSalt: (existingDeviceKey['wrappedAuthSalt'] ?? '').toString(),
          password: rawPassword,
          mnemonicWords: recoveredWords,
        );

        if (unwrapped == null) {
          if (context.mounted) {
            _showStatusDialog(context, 'RECOVERY FAILED', 'THE RECOVERY PHRASE DID NOT MATCH THIS BACKUP.');
          }
          return;
        }

        effectivePinHash = await CryptoEngine.hashPinWithSalt(rawPassword, unwrapped);
        await settingsBox.put('system_crypto_pin', effectivePinHash);
        await settingsBox.put('last_active_crypto_pin_snapshot', effectivePinHash);
      }
    } else {
      debugPrint('POST-SAVE SYNC: device_key.json exists but repo has no note files - nothing to probe or import');
    }

    if (filesToImport.isEmpty) {
      debugPrint('POST-SAVE SYNC: filesToImport empty, stopping here');
      return;
    }

    final notifier = ref.read(localDatabaseProvider.notifier);
    final List<CaptureItem> currentBackedUpItems =
    ref.read(localDatabaseProvider).where((item) => item.backupEnabled).toList();
    for (final item in currentBackedUpItems) {
      await notifier.deleteItem(item.id);
    }
    await notifier.clearSyncQueue();

    int importedCount = 0;
    for (final fileName in filesToImport) {
      try {
        final Map<String, dynamic>? data = await service.fetchNoteFile(fileName);
        if (data == null) continue;

        final String salt = (data['salt'] ?? '').toString();
        final String nonce = (data['nonce'] ?? '').toString();
        final String cyphertext = (data['cyphertext'] ?? '').toString();
        final String title = fileName.endsWith('.json') ? fileName.substring(0, fileName.length - 5) : fileName;

        String content;
        String type;
        if (salt.isEmpty) {
          content = cyphertext;
          type = 'note';
        } else {
          content = await CryptoEngine.decryptProcess(
            CryptoEngine.mergeFromBackup(salt, nonce, cyphertext),
            effectivePinHash,
          );
          if (content == 'DECRYPTION FAULT') continue;
          type = 'encrypted_note';
        }

        final bool inserted = await notifier.insertItem(content, type, title: title, backupEnabled: true);
        if (inserted) importedCount++;
      } catch (_) {
        continue;
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('IMPORTED $importedCount NOTE(S) FROM BACKUP')),
      );
    }
  }

  Future<void> _showMnemonicDisplayDialog(BuildContext context, List<String> words) async {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return PopScope(
          canPop: false,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.dialogBg,
                  border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RECOVERY PHRASE',
                      style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'WRITE THESE 12 WORDS DOWN ON PAPER OR A TRUSTED DEVICE. THEY WILL NEVER BE SHOWN AGAIN.',
                      style: TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.w600, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    _buildMnemonicWordRow(words.sublist(0, 6), theme),
                    const SizedBox(height: 8),
                    _buildMnemonicWordRow(words.sublist(6, 12), theme),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: theme.textMain),
                            child: Text(
                              'I HAVE WRITTEN THIS DOWN',
                              style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMnemonicWordRow(List<String> words, SettingsUiTheme theme) {
    return Row(
      children: List.generate(6, (i) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 5 ? 0 : 4),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
            alignment: Alignment.center,
            child: Text(
              words[i],
              style: TextStyle(color: theme.textMain, fontSize: 9, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }),
    );
  }

  String? _checkMnemonicLockout(Box settingsBox) {
    final int lockoutUntil = settingsBox.get('mnemonic_lockout_until', defaultValue: 0);
    final int currentTime = DateTime.now().millisecondsSinceEpoch;

    if (lockoutUntil > currentTime) {
      final remaining = ((lockoutUntil - currentTime) / 1000).ceil();
      return 'SYSTEM LOCKED - WAIT $remaining SECONDS';
    }
    return null;
  }

  Future<List<String>?> _promptMnemonicRecovery(BuildContext context) async {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    final settingsBox = Hive.box(_boxName);

    final List<TextEditingController> controllers = List.generate(12, (_) => TextEditingController());
    String? lockStringStatus = _checkMnemonicLockout(settingsBox);
    Timer? countdownTimer;

    void ensureCountdownRunning(void Function(void Function()) setState_) {
      if (lockStringStatus == null) return;
      if (countdownTimer != null && countdownTimer!.isActive) return;
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final String? current = _checkMnemonicLockout(settingsBox);
        setState_(() {
          lockStringStatus = current;
        });
        if (current == null) timer.cancel();
      });
    }

    final result = await showGeneralDialog<List<String>?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            ensureCountdownRunning(setDialogState);
            final bool locked = lockStringStatus != null;

            return Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: const TextSelectionThemeData(
                  selectionColor: Color(0x335F0E0D),
                  selectionHandleColor: Color(0xFF5F0E0D),
                  cursorColor: Color(0xFF5F0E0D),
                ),
              ),
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 340,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.dialogBg,
                      border: Border.all(color: theme.dialogBorderColor, width: 0.8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lockStringStatus ?? 'ENTER 12-WORD RECOVERY PHRASE',
                          style: TextStyle(
                            color: locked ? const Color(0xFFEF4444) : theme.textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.05,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _mnemonicFieldRow(controllers.sublist(0, 6), 0, theme, setDialogState, !locked),
                        const SizedBox(height: 8),
                        _mnemonicFieldRow(controllers.sublist(6, 12), 6, theme, setDialogState, !locked),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            InkWell(
                              onTap: () => Navigator.pop(context, null),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
                                child: Text(
                                  'CANCEL',
                                  style: TextStyle(color: isDark ? const Color(0xFF888888) : const Color(0xFF525252), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () async {
                                final activeLock = _checkMnemonicLockout(settingsBox);
                                if (activeLock != null) {
                                  setDialogState(() => lockStringStatus = activeLock);
                                  return;
                                }

                                final List<String> words = controllers.map((c) => c.text.trim().toLowerCase()).toList();
                                final bool allKnown = words.every((w) => CryptoEngine.isValidMnemonicWord(w));
                                final bool checksumOk = allKnown && await CryptoEngine.validateMnemonicChecksum(words);

                                if (checksumOk) {
                                  await settingsBox.put('mnemonic_failed_attempts', 0);
                                  await settingsBox.put('mnemonic_lockout_until', 0);
                                  if (!context.mounted) return;
                                  Navigator.pop(context, words);
                                } else {
                                  int attempts = settingsBox.get('mnemonic_failed_attempts', defaultValue: 0) + 1;
                                  await settingsBox.put('mnemonic_failed_attempts', attempts);
                                  final int penalty = CryptoEngine.lockoutSecondsForAttempt(attempts);
                                  if (penalty > 0) {
                                    await settingsBox.put(
                                      'mnemonic_lockout_until',
                                      DateTime.now().millisecondsSinceEpoch + penalty * 1000,
                                    );
                                  }
                                  setDialogState(() {
                                    lockStringStatus = _checkMnemonicLockout(settingsBox);
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(color: theme.textMain),
                                child: Text(
                                  'COMMIT',
                                  style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    countdownTimer?.cancel();
    return result;
  }

  Widget _mnemonicFieldRow(
      List<TextEditingController> rowControllers,
      int startIndex,
      SettingsUiTheme theme,
      void Function(void Function()) setDialogState,
      bool enabled,
      ) {
    return Row(
      children: List.generate(6, (i) {
        final TextEditingController controller = rowControllers[i];
        final String word = controller.text.trim().toLowerCase();
        final bool isUnknown = word.isNotEmpty && !CryptoEngine.isValidMnemonicWord(word);

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 5 ? 0 : 4),
            child: TextField(
              controller: controller,
              enabled: enabled,
              contextMenuBuilder: (context, state) => const SizedBox.shrink(),
              onChanged: (_) => setDialogState(() {}),
              style: TextStyle(color: theme.textMain, fontSize: 10),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                hintText: '${startIndex + i + 1}',
                hintStyle: TextStyle(color: theme.textSub, fontSize: 9),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: isUnknown ? const Color(0xFF5F0E0D) : theme.dialogBorderColor, width: isUnknown ? 1.2 : 0.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: isUnknown ? const Color(0xFF5F0E0D) : theme.textMain, width: 1.2),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _showSlidingPanel(BuildContext context, String title, List<Widget> children, bool isDark) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          final panelBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
          final textMain = isDark ? Colors.white : Colors.black;
          final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(color: Colors.transparent),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: panelBg,
                      ),
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: borderColor, width: 0.8),
                                      ),
                                      child: Icon(Icons.arrow_back, size: 14, color: textMain),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: textMain,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.02,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(color: borderColor, height: 1, thickness: 0.8),

                            Expanded(
                              child: ListView(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.all(24.0),
                                children: children,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.fastOutSlowIn;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildMenuTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color textMain,
    required Color textSub,
    required Color borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.03),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: textSub, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: textSub),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(String header, String body, Color textMain, Color textSub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: TextStyle(color: textMain, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.05),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(color: textSub, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final theme = SettingsUiTheme(isDark);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          children: [
            Text(
              'SYSTEM SETTINGS',
              style: TextStyle(color: theme.textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.containerBg,
                border: Border.all(color: theme.mainBorderColor, width: 0.8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DARK INTERFACE',
                        style: TextStyle(color: theme.textMain, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.05),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toggle system-wide dark mode',
                        style: TextStyle(color: theme.textSub, fontSize: 10),
                      ),
                    ],
                  ),

                  GestureDetector(
                    onTap: () {
                      ref.read(themeProvider.notifier).toggleTheme();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 44,
                      height: 24,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFDDDDDD),
                        border: Border.all(color: theme.mainBorderColor, width: 0.8),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 120),
                        alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            ValueListenableBuilder(
              valueListenable: Hive.box(_boxName).listenable(keys: ['system_crypto_pin']),
              builder: (context, Box box, _) {
                final String currentPin = box.get('system_crypto_pin', defaultValue: '');

                return _buildMenuTile(
                  title: 'CRYPTOGRAPHIC ACCESS PASSWORD',
                  subtitle: currentPin.isEmpty
                      ? 'SETUP REQUIRED // 6-CHARACTER SECURITY KEY'
                      : 'ACTIVE // MODIFY SECURE TERMINAL DEPLOYMENT KEY',
                  textMain: theme.textMain,
                  textSub: currentPin.isEmpty ? const Color(0xFFEF4444) : theme.textSub,
                  borderColor: theme.mainBorderColor,
                  onTap: () {
                    if (currentPin.isEmpty) {
                      _showCreatePinDialog(context);
                    } else {
                      _promptChangePasswordChallenge(context);
                    }
                  },
                );
              },
            ),

            const SizedBox(height: 12),

            ValueListenableBuilder(
              valueListenable: Hive.box(_boxName).listenable(keys: ['github_access_encrypted']),
              builder: (context, Box box, _) {
                final bool githubReady = box.get('github_access_encrypted') != null;

                return _buildMenuTile(
                  title: 'GITHUB TOKEN STORE',
                  subtitle: githubReady
                      ? 'ACTIVE // MODIFY REPOSITORY BACKUP CREDENTIALS'
                      : 'SETUP REQUIRED // FINE-GRAINED TOKEN + REPOSITORY',
                  textMain: theme.textMain,
                  textSub: githubReady ? theme.textSub : const Color(0xFFEF4444),
                  borderColor: theme.mainBorderColor,
                  onTap: () => _promptGithubAccessChallenge(context),
                );
              },
            ),

            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black : Colors.white,
                border: Border.all(color: theme.mainBorderColor, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DATA UTILITIES',
                    style: TextStyle(color: theme.textMain, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Export or restore persistent application database matrices safely.',
                    style: TextStyle(color: theme.textSub, fontSize: 10.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _handleDataExport,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.mainBorderColor, width: 0.8),
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'EXPORT BACKUP',
                              style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.02),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showRestoreChooserDialog(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.textMain, width: 0.8),
                              color: Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'RESTORE BACKUP',
                              style: TextStyle(color: theme.textMain, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.02),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            Divider(color: theme.mainBorderColor, thickness: 0.8),

            _buildMenuTile(
              title: 'USER GUIDE',
              subtitle: 'Overview of system infrastructure panels',
              textMain: theme.textMain,
              textSub: theme.textSub,
              borderColor: theme.mainBorderColor,
              onTap: () => _showSlidingPanel(
                context,
                'USER GUIDE',
                [
                  _buildInfoSection(
                      '01 // SYSTEM ROOT ENGINE',
                      'Initializes global asynchronous reactive state loops using Riverpod. It maps runtime dependencies directly upon app activation and tracks low-level mutations securely. Bypasses persistent disk hangs via strict corruption validation parameters, completely ensuring zero structural app freezing or unhandled memory loops.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '02 // GATEWAY LAYER (SPLASH SCREEN)',
                      'Handles high-performance layout warm-ups during frame construction phases. Intercepts the primary platform loading sequence, executing an isolated 2-second linear opacity rendering track (Fade -> Visual Suspension -> Purge) that seamlessly aligns the system layout context with your previous light or dark UI settings to eradicate aggressive boot-flash anomalies completely.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '03 // STRUCTURAL HUB NAVIGATION',
                      'A streamlined typography-focused matrix navigation track that maps layout views safely. Built with absolute override layout parameters that dictate viewport allocation during active software keyboard states. Instead of forcing physical view compression or breaking cross-axis element alignments, incoming OS input windows act as smooth layer overlays.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '04 // MATRIX TIMELINE COMPONENT',
                      'Renders a massive, low-fatigue 13-column structural layout tracking 365 daily block elements simultaneously. Darkened tracking indicators pinpoint precise historical data allocation slots, while empty slots define exact leftover capacity indexes inside the current runtime period.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '05 // QUICKNOTE SANDBOX MODULE',
                      'Employs an anti-collapse scrolling viewport configuration tied directly to explicit layout boundaries and custom constraints. This forces live character generation streams to dynamically recalculate remaining box space when virtual keyboards arise, keeping active text editing targets completely visible.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '06 // INTERFACE REGULATION CONTROLS',
                      'Executes direct UI inversions via a streamlined state-toggle mechanism. Connects configuration panels into hardware-accelerated right-to-left slide transitions locked at a precise 1.0 width factor constraint. Sub-sheets completely obscure underlying layers, eliminating unnecessary drop-shadow re-renders to maximize device refresh rates.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '07 // DATA IMPORT/EXPORT SYSTEM',
                      'Features custom serialization engines that loop through application states, converting model entries into raw standardized JSON bytes. Built-in file picking mechanics handle direct filesystem interaction to securely transfer data without utilizing external cloud proxies or intermediate networks.',
                      theme.textMain, theme.textSub
                  ),
                ],
                isDark,
              ),
            ),

            _buildMenuTile(
              title: 'DATA SECURITY',
              subtitle: 'Information encryption & local cache schemas',
              textMain: theme.textMain,
              textSub: theme.textSub,
              borderColor: theme.mainBorderColor,
              onTap: () => _showSlidingPanel(
                context,
                'DATA SECURITY',
                [
                  _buildInfoSection(
                      '01 // STORAGE PIPELINE (NOSQL ENGINE)',
                      'Rocen avoids slow, heavy relational SQL frameworks entirely. The application operates exclusively on a lightning-fast NoSQL key-value architecture powered by Hive. Text strings and file indicators are encoded directly into raw binary streams written inside dedicated sandbox partitions allocated to the app hardware space.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '02 // BOX CONTAINER MATRIX',
                      'Data storage blocks are separated into dedicated, context-isolated data compartments called "Boxes" (e.g., rocen_captures_box). Structural indexes replace classic relational tables, creating lightweight data access pathways that protect historical databases from schema breaking risks when fields expand.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '03 // MEMORY-FIRST BUFFER PIPELINE',
                      'Data structures are loaded straight into fast active RAM buffers during bootup. Read tasks operate directly inside this memory layer with zero disk latency. Create, update, and delete actions instantly change the cache array for direct visual updates, then stream down onto device hardware storage asynchronously.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '04 // CORRUPTION REPAIR FAILSAFE',
                      'A custom try-catch validation engine checks the integrity of database boxes during initialization. If a database interruption (like a sudden power drop) compromises data syntax, the broken data block is instantly isolated to prevent system boot loops, and initialized safely back to standard parameters.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '05 // APPLICATION PERMISSIONS OUTLINE',
                      'The application manifest explicitly excludes unnecessary network communication channels, background telemetry monitors, and analytical scrapers. Your information is physically unable to leave the system via background connection bridges.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '06 // CRYPTOGRAPHIC KEY WRAPPING',
                      'Activating the CRYPTOGRAPHIC ACCESS PASSWORD applies an isolated user verification requirement. Secure components (like encrypted_note parameters) evaluate this key matching verification block locally. Changing or deleting the security password immediately purges corresponding key-dependent items from storage to guarantee absolute protection against physical file manipulation.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '07 // OFF-GRID FILE EXPORT UTILITY',
                      'Backup operations run on standard local UTF-8 data conversion engines. Generated data is written to user-designated folders via a native document explorer pipeline. Raw schema text is never transmitted through background trackers or third-party data processing endpoints.',
                      theme.textMain, theme.textSub
                  ),
                ],
                isDark,
              ),
            ),

            _buildMenuTile(
              title: 'PRIVACY POLICY',
              subtitle: 'Application definitions and core manifest details',
              textMain: theme.textMain,
              textSub: theme.textSub,
              borderColor: theme.mainBorderColor,
              onTap: () => _showSlidingPanel(
                context,
                'PRIVACY POLICY',
                [
                  _buildInfoSection(
                      '01 // APPLICATION DESCRIPTION',
                      'Rocen is a hyper-focused minimalist system blueprint designed to run high-utility tools without backend software bloat or visual clutter.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '02 // SYSTEM AUTHORSHIP',
                      'Engineered and assembled by Darshseraphic.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '03 // PURPOSE & DESIGN METHODOLOGY',
                      'Built to mitigate screen fatigue through a stark brutalist interface style, intentional whitespace, and highly structured typographic layouts.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '04 // DEVELOPMENT TIMELINE MATRIX',
                      'Initial core system conceptualization, wireframing, and final architecture completion finalized over a highly compressed 24-hour rapid development sprint.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '05 // ABSOLUTE ZERO DATA ACCUMULATION',
                      'This framework operates with a strict zero-telemetry policy. There are no analytics packages, usage tracking monitors, remote crash trackers, or cloud-based data bridges written into the codebase. All workspace activity remains strictly contained on your local device.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '06 // AIR-GAPPED HARDWARE ISOLATION',
                      'The application runs entirely within an air-gapped system methodology. Without network permissions or server communication layers configured in its structural layer, user interactions are kept private, secure, and permanently anchored inside the isolated sandbox space of your hardware.',
                      theme.textMain, theme.textSub
                  ),
                  _buildInfoSection(
                      '07 // USER-OWNED STORAGE ARCHITECTURE',
                      'You retain absolute, exclusive ownership of your data files. The system cannot read, change, or access stored items outside its specific offline database context. Deleting the application instantly wipes all local cache directories from internal storage arrays.',
                      theme.textMain, theme.textSub
                  ),
                ],
                isDark,
              ),
            ),

            _buildMenuTile(
              title: 'WEBSITE',
              subtitle: 'Access outward system project portals',
              textMain: theme.textMain,
              textSub: theme.textSub,
              borderColor: theme.mainBorderColor,
              onTap: _launchWebsiteUrl,
            ),

            _buildMenuTile(
              title: 'FEEDBACK',
              subtitle: 'Report pipeline anomalies or system logs',
              textMain: theme.textMain,
              textSub: theme.textSub,
              borderColor: theme.mainBorderColor,
              onTap: _launchFeedbackUrl,
            ),

            const SizedBox(height: 48),

            Center(
              child: Text(
                'BUILD BY DARSHSERPHIC',
                style: TextStyle(
                  color: theme.textSub.withOpacity(0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.12,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}