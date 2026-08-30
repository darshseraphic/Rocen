import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../core/database.dart';
import '../core/crypto_engine.dart';
import '../core/github_backup_service.dart';
import '../core/password_state_manager.dart';
import '../core/debug_log.dart';
import 'quicknote.dart';
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
    mainBorderColor =
        isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    dialogBorderColor =
        isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
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
  static const MethodChannel _screenSecurityChannel =
      MethodChannel('com.darshseraphic.rocen/screen_security');

  Future<void> _setScreenshotProtection(bool enabled) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _screenSecurityChannel.invokeMethod(
          enabled ? 'preventScreenshotOn' : 'preventScreenshotOff');
    } catch (_) {}
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
      secureDebugLog('System Error: Could not execute route handshake to $url');
    }
  }

  Future<void> _launchFeedbackUrl() async {
    final Uri url = Uri.parse('https://rocen.lovable.app/feedback');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      secureDebugLog('System Error: Could not execute route handshake to $url');
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

  Future<void> _purgeEncryptedNotesOnBruteForce() async {
    final currentItems = ref.read(localDatabaseProvider);
    final targetsToPurge =
        currentItems.where((item) => item.type == 'encrypted_note').toList();

    for (var target in targetsToPurge) {
      await ref.read(localDatabaseProvider.notifier).deleteItem(target.id);
    }
  }

  void _showAcknowledgeDialog(
      BuildContext context, String title, String message) {
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
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.02),
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
                        'ACKNOWLEDGE',
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
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 11,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.02),
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
    // Delegates to the single, fully up-to-date push implementation in
    // quicknote.dart (opaque remoteFileId filenames, encrypted title
    // embedding, timestamps, legacy migration, zero-decrypt guard for
    // notes pending review) rather than maintaining a second copy of this
    // logic here that can silently drift out of sync with it.
    await pushAllBackupEnabledNotes(ref);
  }

  Future<void> _handleDataExport() async {
    unawaited(_pushFullBackupSync());

    try {
      final String serializedJson =
          ref.read(localDatabaseProvider.notifier).exportToSchemaJson();
      final String timestamp =
          DateTime.now().toString().split(' ').first.replaceAll('-', '_');
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
        _showStatusDialog(context, 'EXPORT FAIL',
            'CRITICAL ERROR INITIALIZING SEQUENCE: ${e.toString()}');
      }
    }
  }

  Future<void> _handleDataImport() async {
    try {
      final FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.any);

      if (result == null || result.files.single.path == null) return;

      final File pickedFile = File(result.files.single.path!);
      final String fileContents = await pickedFile.readAsString();

      final bool isSuccess = await ref
          .read(localDatabaseProvider.notifier)
          .importFromSchemaJson(fileContents);

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
        _showStatusDialog(context, 'IMPORT FAIL',
            'PROCESS ABORTED DUE TO ENCODING EXCEPTIONS: ${e.toString()}');
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
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.02),
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
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: theme.dialogBorderColor,
                                    width: 0.8)),
                            alignment: Alignment.center,
                            child: Text('GITHUB',
                                style: TextStyle(
                                    color: theme.textMain,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.02)),
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
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: theme.dialogBorderColor,
                                    width: 0.8)),
                            alignment: Alignment.center,
                            child: Text('LOCAL',
                                style: TextStyle(
                                    color: theme.textMain,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.02)),
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
      _showStatusDialog(context, 'GITHUB NOT CONFIGURED',
          'SET UP THE GITHUB TOKEN STORE FIRST BEFORE RESTORING FROM GITHUB.');
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
      barrierDismissible: false,
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
                      border: Border.all(
                          color: theme.dialogBorderColor, width: 0.8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayHeaderTitle,
                          style: TextStyle(
                            color: (hasPinFailed || lockStringStatus != null)
                                ? const Color(0xFFEF4444)
                                : theme.textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.05,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Builder(builder: (context) {
                          Color currentFieldBorderColor;
                          if (hasPinFailed || lockStringStatus != null) {
                            currentFieldBorderColor = const Color(0xFFEF4444);
                          } else {
                            currentFieldBorderColor = theme.dialogBorderColor;
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: currentFieldBorderColor,
                                width:
                                    (hasPinFailed || lockStringStatus != null)
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
                                color:
                                    (hasPinFailed || lockStringStatus != null)
                                        ? const Color(0xFFEF4444)
                                        : theme.textMain,
                                fontSize: 16,
                                letterSpacing: 4,
                                fontWeight: FontWeight.bold,
                              ),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (hasPinFailed) hasPinFailed = false;
                                });
                              },
                              decoration: const InputDecoration(
                                  counterText: '',
                                  border: InputBorder.none,
                                  isDense: true),
                            ),
                          );
                        }),
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
                                        color: theme.dialogBorderColor,
                                        width: 0.8)),
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

                                final bool isPinValid = await CryptoEngine
                                    .verifyPinWithHardwareBinding(
                                        pinVerifyController.text, globalPin);

                                if (isPinValid) {
                                  final String rawPassword =
                                      pinVerifyController.text;
                                  await settingsBox.put(
                                      'secure_failed_attempts', 0);
                                  await settingsBox.put(
                                      'secure_lockout_until', 0);

                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  if (!screenContext.mounted) return;

                                  try {
                                    final String? unwrappedForRestore =
                                        await CryptoEngine.hardwareUnwrap(
                                            accessBlob,
                                            keyAlias: CryptoEngine
                                                .githubTokenKeyAlias);
                                    if (unwrappedForRestore == null) {
                                      secureDebugLog(
                                          '[settings] hardwareUnwrap failed for githubTokenKeyAlias during restore - treating stored blob as software-encrypted only');
                                    }
                                    final String accessJson =
                                        await CryptoEngine.decryptProcess(
                                            unwrappedForRestore ?? accessBlob,
                                            globalPin);
                                    if (accessJson == 'DECRYPTION FAULT') {
                                      if (screenContext.mounted) {
                                        _showStatusDialog(
                                            screenContext,
                                            'RESTORE ERROR',
                                            'STORED GITHUB CREDENTIALS COULD NOT BE DECRYPTED WITH THE CURRENT PASSWORD.');
                                      }
                                      return;
                                    }
                                    final Map<String, dynamic> access =
                                        jsonDecode(accessJson);
                                    final String? token =
                                        access['token'] as String?;
                                    final String? repo =
                                        access['repo'] as String?;
                                    if (token == null || repo == null) {
                                      if (screenContext.mounted) {
                                        _showStatusDialog(
                                            screenContext,
                                            'RESTORE ERROR',
                                            'STORED TOKEN OR REPOSITORY WAS EMPTY.');
                                      }
                                      return;
                                    }

                                    if (!screenContext.mounted) return;
                                    await _handlePostSaveGithubSync(
                                        screenContext,
                                        token,
                                        repo,
                                        rawPassword,
                                        globalPin,
                                        isExplicitRestore: true);
                                  } catch (e) {
                                    if (screenContext.mounted) {
                                      _showStatusDialog(
                                          screenContext,
                                          'RESTORE ERROR',
                                          'UNEXPECTED ERROR: $e');
                                    }
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
                                    await _purgeEncryptedNotesOnBruteForce();
                                    await settingsBox.put(
                                        'secure_failed_attempts', 0);
                                    await settingsBox.put(
                                        'secure_lockout_until', 0);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    if (!screenContext.mounted) return;
                                    _showAcknowledgeDialog(
                                        screenContext,
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
                                    if (lockStringStatus == null)
                                      hasPinFailed = true;
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
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'RESTORING WILL PERMANENTLY WIPE ALL LOGGED RECORDS FROM RECENT SESSIONS AND REPLACE THEM WITH THE SELECTED BACKUP MATRIX. THIS CANNOT BE UNDONE.',
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 11.5,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: theme.dialogBorderColor, width: 0.8),
                          ),
                          child: Text(
                            'CANCEL',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF888888)
                                  : const Color(0xFF525252),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 6),
                          decoration:
                              const BoxDecoration(color: Color(0xFFEF4444)),
                          child: const Text(
                            'RESTORE DATA',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
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

    final TextEditingController pinController =
        TextEditingController(text: initialValue);
    final Set<String> hapticFiredFor = {};

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final List<(String, bool)> statuses =
                CryptoEngine.passwordRequirementStatus(pinController.text);
            final int satisfiedCount = statuses.where((s) => s.$2).length;
            final double ratio =
                statuses.isEmpty ? 0.0 : satisfiedCount / statuses.length;
            const Color weakColor = Color(0xFF7A0000);
            final Color progressColor =
                Color.lerp(weakColor, theme.textMain, ratio) ?? theme.textMain;

            for (final s in statuses) {
              if (s.$2 && !hapticFiredFor.contains(s.$1)) {
                HapticFeedback.lightImpact();
                hapticFiredFor.add(s.$1);
              } else if (!s.$2 && hapticFiredFor.contains(s.$1)) {
                hapticFiredFor.remove(s.$1);
              }
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
                      border: Border.all(
                          color: theme.dialogBorderColor, width: 0.8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SETUP CRYPTOGRAPHY PASSWORD',
                          style: TextStyle(
                              color: theme.textMain,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.05),
                        ),
                        const SizedBox(height: 20),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutQuart,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: pinController.text.isEmpty
                                  ? theme.dialogBorderColor
                                  : progressColor,
                              width: pinController.text.isEmpty ? 0.8 : 1.2,
                            ),
                          ),
                          child: TextField(
                            controller: pinController,
                            keyboardType: TextInputType.text,
                            maxLength: 32,
                            obscureText: true,
                            obscuringCharacter: '#',
                            cursorColor: theme.textMain,
                            autofocus: true,
                            onChanged: (val) => setDialogState(() {}),
                            style: TextStyle(
                              color: pinController.text.isEmpty
                                  ? theme.textMain
                                  : progressColor,
                              fontSize: 16,
                              letterSpacing: 4,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 3,
                                color: theme.dialogBorderColor,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(begin: 0.0, end: ratio),
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutQuart,
                                  builder: (context, value, child) {
                                    return FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: value.clamp(0.0, 1.0),
                                      child: Container(color: progressColor),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(ratio * 100).round()}%',
                              style: TextStyle(
                                  color: progressColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.02),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: statuses
                              .map((s) =>
                                  _buildPasswordRequirementRow(s.$1, s.$2))
                              .toList(),
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
                                      color: theme.dialogBorderColor,
                                      width: 0.8),
                                ),
                                child: Text(
                                  'CANCEL',
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF888888)
                                        : const Color(0xFF525252),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: !CryptoEngine.isPasswordComplexityValid(
                                      pinController.text)
                                  ? null
                                  : () {
                                      final typedPin = pinController.text;
                                      Navigator.pop(context);
                                      _showAreYouSureDialog(context, typedPin);
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: CryptoEngine.isPasswordComplexityValid(
                                          pinController.text)
                                      ? theme.textMain
                                      : theme.textMain.withOpacity(0.2),
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
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ARE YOU SURE YOU WANT TO SET THIS PASSWORD?',
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.02),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: theme.dialogBorderColor, width: 0.8),
                          ),
                          child: Text(
                            'CANCEL',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF888888)
                                  : const Color(0xFF525252),
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

                          final settingsBox = Hive.box(_boxName);
                          final bool rooted =
                              await CryptoEngine.isDeviceRooted();
                          await settingsBox.put('kdf_hardened', rooted);

                          final securePinHash =
                              await CryptoEngine.hashPin(typedPin);

                          await settingsBox.put(
                              'system_crypto_pin', securePinHash);
                          await settingsBox.put(
                              'last_active_crypto_pin_snapshot', securePinHash);

                          final String? hwWrappedPin =
                              await CryptoEngine.hardwareWrap(securePinHash,
                                  keyAlias: CryptoEngine.passwordKeyAlias);
                          if (hwWrappedPin != null) {
                            await settingsBox.put(
                                'hw_wrapped_pin', hwWrappedPin);
                          }

                          if (screenContext.mounted) {
                            _showForgotWarningDialog(screenContext);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
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
    final buttonBg = isDark ? Colors.white : Colors.black;
    final buttonText = isDark ? Colors.black : Colors.white;

    showGeneralDialog(
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
                width: 300,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.dialogBg,
                  border:
                      Border.all(color: theme.dialogBorderColor, width: 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'CRITICAL NOTICE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: theme.textMain,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.05),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'IF YOU FORGET YOUR PASSWORD, YOUR 12-WORD RECOVERY PHRASE IS THE ONLY WAY BACK IN. WITHOUT IT, YOUR LOCAL DATA CANNOT BE RECOVERED - ONLY CLEARED AND RESTARTED FROM SCRATCH.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: theme.textMain,
                          fontSize: 12,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.02),
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
                          'ACKNOWLEDGE',
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
      barrierDismissible: false,
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
                      border: Border.all(
                          color: theme.dialogBorderColor, width: 0.8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayHeaderTitle,
                          style: TextStyle(
                            color: (hasPinFailed || lockStringStatus != null)
                                ? const Color(0xFFEF4444)
                                : theme.textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.05,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Builder(builder: (context) {
                          Color currentFieldBorderColor;
                          if (hasPinFailed || lockStringStatus != null) {
                            currentFieldBorderColor = const Color(0xFFEF4444);
                          } else {
                            currentFieldBorderColor = theme.dialogBorderColor;
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: currentFieldBorderColor,
                                width:
                                    (hasPinFailed || lockStringStatus != null)
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
                                color:
                                    (hasPinFailed || lockStringStatus != null)
                                        ? const Color(0xFFEF4444)
                                        : theme.textMain,
                                fontSize: 16,
                                letterSpacing: 4,
                                fontWeight: FontWeight.bold,
                              ),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (hasPinFailed) hasPinFailed = false;
                                });
                              },
                              decoration: const InputDecoration(
                                  counterText: '',
                                  border: InputBorder.none,
                                  isDense: true),
                            ),
                          );
                        }),
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
                                        color: theme.dialogBorderColor,
                                        width: 0.8)),
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

                                final bool isPinValid = await CryptoEngine
                                    .verifyPinWithHardwareBinding(
                                        pinVerifyController.text, globalPin);

                                if (isPinValid) {
                                  final String rawOldPassword =
                                      pinVerifyController.text;
                                  await settingsBox.put(
                                      'secure_failed_attempts', 0);
                                  await settingsBox.put(
                                      'secure_lockout_until', 0);

                                  final bool githubConfigured = settingsBox
                                          .get('github_access_encrypted') !=
                                      null;

                                  PasswordStateResult? stateResult;
                                  GithubBackupService? preconditionService;
                                  if (githubConfigured) {
                                    if (!context.mounted) return;
                                    _showSavingIndicatorDialog(context, isDark);

                                    preconditionService =
                                        await _buildGithubServiceFromStoredCredentials(
                                            globalPin);

                                    if (preconditionService != null) {
                                      stateResult = await PasswordStateManager
                                          .checkState(preconditionService);
                                    }

                                    if (context.mounted) {
                                      Navigator.of(context, rootNavigator: true)
                                          .pop();
                                    }

                                    final bool checkOk = stateResult != null &&
                                        (stateResult.comparison ==
                                                PasswordStateComparison
                                                    .synchronized ||
                                            stateResult.comparison ==
                                                PasswordStateComparison
                                                    .noRemoteStateYet);

                                    if (!checkOk) {
                                      if (!context.mounted) return;
                                      final String message = stateResult ==
                                                  null ||
                                              stateResult.comparison ==
                                                  PasswordStateComparison
                                                      .checkFailed
                                          ? 'COULD NOT VERIFY THE CURRENT PASSWORD STATE WITH GITHUB. CHECK YOUR CONNECTION AND TRY AGAIN — PASSWORD CHANGES REQUIRE AN ONLINE CHECK WHEN GITHUB BACKUP IS ENABLED.'
                                          : stateResult.comparison ==
                                                  PasswordStateComparison
                                                      .behindRemote
                                              ? 'YOUR PASSWORD WAS ALREADY CHANGED ON ANOTHER DEVICE${stateResult.remoteChangedByDeviceId != null ? " (${stateResult.remoteChangedByDeviceId})" : ""}. ENTER THE CURRENT PASSWORD AND YOUR RECOVERY PHRASE TO UPDATE THIS DEVICE BEFORE CHANGING IT AGAIN.'
                                          : 'THIS DEVICE AND ANOTHER DEVICE HAVE CONFLICTING PASSWORD STATES. RESOLVE THIS BEFORE CHANGING YOUR PASSWORD AGAIN — SEE RECOVERY.';
                                      _showStatusDialog(context,
                                          'PASSWORD CHANGE UNAVAILABLE', message);
                                      return;
                                    }
                                  }

                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  if (!screenContext.mounted) return;
                                  _showNewPasswordDialog(
                                      screenContext,
                                      globalPin,
                                      rawOldPassword,
                                      stateResult,
                                      preconditionService);
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
                                    await _purgeEncryptedNotesOnBruteForce();
                                    await settingsBox.put(
                                        'secure_failed_attempts', 0);
                                    await settingsBox.put(
                                        'secure_lockout_until', 0);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    if (!screenContext.mounted) return;
                                    _showAcknowledgeDialog(
                                        screenContext,
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
                                    if (lockStringStatus == null)
                                      hasPinFailed = true;
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
    ).then((_) => countdownTimer?.cancel());
  }

  void _showNewPasswordDialog(
      BuildContext context,
      String oldPinHash,
      String rawOldPassword,
      PasswordStateResult? preconditionState,
      GithubBackupService? preconditionService) {
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
                      border: Border.all(
                          color: theme.dialogBorderColor, width: 0.8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ENTER NEW PASSWORD',
                            style: TextStyle(
                                color: theme.textMain,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.05)),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.dialogBorderColor,
                              width: 0.8,
                            ),
                          ),
                          child: TextField(
                            controller: pinController,
                            keyboardType: TextInputType.text,
                            maxLength: 32,
                            obscureText: true,
                            obscuringCharacter: '#',
                            cursorColor: theme.textMain,
                            autofocus: true,
                            onChanged: (val) => setDialogState(() {}),
                            style: TextStyle(
                              color: theme.textMain,
                              fontSize: 16,
                              letterSpacing: 4,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Builder(builder: (context) {
                          final statuses =
                              CryptoEngine.passwordRequirementStatus(
                                  pinController.text);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: statuses
                                .map((s) =>
                                    _buildPasswordRequirementRow(s.$1, s.$2))
                                .toList(),
                          );
                        }),
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
                                        color: theme.dialogBorderColor,
                                        width: 0.8)),
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
                              onTap: !CryptoEngine.isPasswordComplexityValid(
                                      pinController.text)
                                  ? null
                                  : () async {
                                      final String newPassword =
                                          pinController.text;
                                      Navigator.pop(context);
                                      if (!screenContext.mounted) return;
                                      await _runPasswordChangeWithProgressModal(
                                          screenContext,
                                          oldPinHash,
                                          rawOldPassword,
                                          newPassword,
                                          preconditionState: preconditionState,
                                          preconditionService:
                                              preconditionService);
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: CryptoEngine.isPasswordComplexityValid(
                                          pinController.text)
                                      ? theme.textMain
                                      : theme.textMain.withOpacity(0.2),
                                ),
                                child: Text('CONFIRM',
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.black
                                            : Colors.white,
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
              ),
            );
          },
        );
      },
    );
  }

  /// Runs the actual password-rotation sequence. The crypto/KDF/note
  /// migration/device-key/GitHub logic and its ordering are UNCHANGED
  /// from before this UX pass — every step below runs in exactly the
  /// same order, with exactly the same conditions, as before. The only
  /// additions are:
  ///   - `onProgress(status)` calls immediately before each real,
  ///     already-existing async operation, so a caller can show what's
  ///     actually happening rather than a silent gap. These calls report
  ///     on real state transitions already present in this function —
  ///     they do not add, remove, delay, or reorder any operation.
  ///   - `onRequestMnemonic` replaces the direct call to
  ///     `_promptMnemonicRecovery(context)` with an injectable function
  ///     of the same signature, so the caller can render the recovery
  ///     phrase entry as a state of its own modal instead of this
  ///     function opening a second, separate dialog. The condition under
  ///     which it's invoked, and what happens with its result, are
  ///     unchanged.
  /// Single non-dismissible modal that drives the entire password-change
  /// UX: progress spinner states, the embedded recovery-phrase entry
  /// state (when reached), and the terminal success/failure state — all
  /// as content changes within ONE dialog, rather than separate dialogs
  /// popping in sequence. This function owns no crypto/rotation logic of
  /// its own; it only renders whatever `_executePasswordChange` reports
  /// via its `onProgress`/`onRequestMnemonic`/`onComplete` callbacks. The
  /// rotation's own logic and ordering are exactly what they were before
  /// this modal existed — see the comments on `_executePasswordChange`.
  Future<void> _runPasswordChangeWithProgressModal(
    BuildContext screenContext,
    String oldPinHash,
    String rawOldPassword,
    String newPassword, {
    PasswordStateResult? preconditionState,
    GithubBackupService? preconditionService,
  }) async {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);

    // Modal-local state, mutated only via setModalState from inside the
    // dialog's own StatefulBuilder.
    String status = 'ENCRYPTING NOTES...';
    bool isEntryStep = false;
    bool isTerminal = false;
    bool terminalSuccess = false;
    bool terminalGithubOk = true;
    String terminalTitle = '';
    String terminalMessage = '';

    // Recovery-phrase entry state, mirroring _promptMnemonicRecovery's
    // own fields exactly, since this reuses the same _mnemonicFieldRow
    // widget and the same validation/lockout logic.
    final settingsBox = Hive.box(_boxName);
    final List<TextEditingController> mnemonicControllers =
        List.generate(12, (_) => TextEditingController());
    final List<FocusNode> mnemonicFocusNodes =
        List.generate(12, (_) => FocusNode());
    String? lockStringStatus = _checkMnemonicLockout(settingsBox);
    bool showValidationError = false;
    Timer? countdownTimer;
    Completer<List<String>?>? mnemonicCompleter;

    late void Function(void Function()) setModalState;
    bool passwordChangeStarted = false;

    void ensureCountdownRunning() {
      if (lockStringStatus == null) return;
      if (countdownTimer != null && countdownTimer!.isActive) return;
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final String? current = _checkMnemonicLockout(settingsBox);
        setModalState(() {
          lockStringStatus = current;
        });
        if (current == null) timer.cancel();
      });
    }

    await showGeneralDialog<void>(
      context: screenContext,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, anim1, anim2) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            setModalState = setState;

            // Kick off the actual rotation exactly once, on first build,
            // wired to update this same modal's state as it progresses.
            // This mirrors exactly what the old code did (call
            // _executePasswordChange, await it) — the only difference is
            // WHERE the progress is shown, not what runs or in what order.
            if (!passwordChangeStarted) {
              passwordChangeStarted = true;
              Future.microtask(() async {
                await _executePasswordChange(
                  screenContext,
                  oldPinHash,
                  rawOldPassword,
                  newPassword,
                  preconditionState: preconditionState,
                  preconditionService: preconditionService,
                  onProgress: (newStatus) {
                    if (newStatus == 'DONE') return; // terminal handled below
                    setState(() {
                      status = newStatus;
                    });
                  },
                  onRequestMnemonic: (ctx) {
                    mnemonicCompleter = Completer<List<String>?>();
                    setState(() {
                      status = 'CHECKING RECOVERY...';
                      isEntryStep = true;
                    });
                    ensureCountdownRunning();
                    return mnemonicCompleter!.future;
                  },
                  onComplete: (success, githubOk) {
                    setState(() {
                      isEntryStep = false;
                      isTerminal = true;
                      terminalSuccess = success;
                      terminalGithubOk = githubOk;
                      if (!success) {
                        terminalTitle = 'PASSWORD CHANGE FAILED';
                        terminalMessage =
                            'YOUR ENCRYPTED NOTES COULD NOT BE MIGRATED TO THE NEW PASSWORD. NOTHING WAS CHANGED — YOUR OLD PASSWORD IS STILL ACTIVE AND YOUR NOTES ARE UNTOUCHED.';
                      } else if (githubOk) {
                        terminalTitle = 'PASSWORD UPDATED';
                        terminalMessage =
                            'YOUR PASSWORD HAS BEEN CHANGED SUCCESSFULLY.';
                      } else {
                        terminalTitle =
                            'PASSWORD UPDATED — GITHUB SYNC NEEDS ATTENTION';
                        terminalMessage =
                            'YOUR PASSWORD WAS CHANGED AND YOUR NOTES ARE SAFE, BUT YOUR STORED GITHUB CREDENTIALS COULD NOT BE FULLY RE-ENCRYPTED. RE-ENTER YOUR GITHUB TOKEN IN SETTINGS TO RESTORE SYNC.';
                      }
                    });
                  },
                );
              });
            }

            return PopScope(
              // Non-dismissible and navigation-blocked until a terminal
              // state is reached, per the requirement that the user
              // cannot navigate away mid-operation.
              canPop: isTerminal,
              child: Theme(
                data: Theme.of(dialogContext).copyWith(
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
                      width: isEntryStep ? 340 : 260,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.dialogBg,
                        border: Border.all(
                          color: showValidationError
                              ? const Color(0xFF5F0E0D)
                              : theme.dialogBorderColor,
                          width: showValidationError ? 1.4 : 0.8,
                        ),
                      ),
                      child: isTerminal
                          ? _buildTerminalState(
                              theme,
                              isDark,
                              terminalTitle,
                              terminalMessage,
                              onAcknowledge: () =>
                                  Navigator.of(dialogContext).pop(),
                            )
                          : isEntryStep
                              ? _buildMnemonicEntryState(
                                  theme,
                                  isDark,
                                  mnemonicControllers,
                                  mnemonicFocusNodes,
                                  lockStringStatus,
                                  showValidationError,
                                  setState,
                                  settingsBox,
                                  onCancel: () {
                                    mnemonicCompleter?.complete(null);
                                  },
                                  onSubmit: (words) {
                                    mnemonicCompleter?.complete(words);
                                  },
                                  onValidationError: () {
                                    setState(() {
                                      showValidationError = true;
                                      lockStringStatus =
                                          _checkMnemonicLockout(settingsBox);
                                    });
                                  },
                                  onFieldEdited: () {
                                    showValidationError = false;
                                  },
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: theme.textMain),
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      status,
                                      style: TextStyle(
                                          color: theme.textMain,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.05),
                                    ),
                                  ],
                                ),
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
    for (final c in mnemonicControllers) {
      c.dispose();
    }
    for (final f in mnemonicFocusNodes) {
      f.dispose();
    }
  }

  Widget _buildTerminalState(
    SettingsUiTheme theme,
    bool isDark,
    String title,
    String message, {
    required VoidCallback onAcknowledge,
  }) {
    final buttonBg = isDark ? Colors.white : Colors.black;
    final buttonText = isDark ? Colors.black : Colors.white;
    return Column(
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
              fontWeight: FontWeight.w500,
              letterSpacing: 0.02),
        ),
        const SizedBox(height: 24),
        InkWell(
          onTap: onAcknowledge,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(color: buttonBg),
            alignment: Alignment.center,
            child: Text(
              'ACKNOWLEDGE',
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
    );
  }

  Widget _buildMnemonicEntryState(
    SettingsUiTheme theme,
    bool isDark,
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
    String? lockStringStatus,
    bool showValidationError,
    void Function(void Function()) setDialogState,
    Box settingsBox, {
    required void Function() onCancel,
    required void Function(List<String> words) onSubmit,
    required void Function() onValidationError,
    required void Function() onFieldEdited,
  }) {
    final bool locked = lockStringStatus != null;
    return Column(
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
        _mnemonicFieldRow(
          controllers.sublist(0, 6),
          focusNodes.sublist(0, 6),
          0,
          theme,
          setDialogState,
          !locked,
          onFieldEdited: onFieldEdited,
        ),
        const SizedBox(height: 8),
        _mnemonicFieldRow(
          controllers.sublist(6, 12),
          focusNodes.sublist(6, 12),
          6,
          theme,
          setDialogState,
          !locked,
          onFieldEdited: onFieldEdited,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            InkWell(
              onTap: onCancel,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                    border:
                        Border.all(color: theme.dialogBorderColor, width: 0.8)),
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
                final activeLock = _checkMnemonicLockout(settingsBox);
                if (activeLock != null) {
                  setDialogState(() {});
                  return;
                }

                final List<String> words = controllers
                    .map((c) => c.text.trim().toLowerCase())
                    .toList();
                final bool allFilled = words.every((w) => w.isNotEmpty);
                final bool allKnown = allFilled &&
                    words.every((w) => CryptoEngine.isValidMnemonicWord(w));
                final bool checksumOk = allKnown &&
                    await CryptoEngine.validateMnemonicChecksum(words);

                if (checksumOk) {
                  await settingsBox.put('mnemonic_failed_attempts', 0);
                  await settingsBox.put('mnemonic_lockout_until', 0);
                  onSubmit(words);
                } else {
                  int attempts = settingsBox.get('mnemonic_failed_attempts',
                          defaultValue: 0) +
                      1;
                  await settingsBox.put('mnemonic_failed_attempts', attempts);
                  final int penalty =
                      CryptoEngine.lockoutSecondsForAttempt(attempts);
                  if (penalty > 0) {
                    await settingsBox.put(
                      'mnemonic_lockout_until',
                      DateTime.now().millisecondsSinceEpoch + penalty * 1000,
                    );
                  }
                  onValidationError();
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: theme.textMain),
                child: Text(
                  'COMMIT',
                  style: TextStyle(
                      color: isDark ? Colors.black : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _executePasswordChange(
    BuildContext context,
    String oldPinHash,
    String rawOldPassword,
    String newPassword, {
    /// The result of the mandatory online precondition check performed
    /// before this function was ever called (see the old-password-verify
    /// success handler). Null only when GitHub backup isn't configured
    /// at all, in which case there's no shared state to publish to.
    /// When non-null, `observedRefSha` is reused as the conditional
    /// write's expected parent, so the publish is conditioned on the
    /// exact state the user's rotation was approved against — not a
    /// fresh re-read that could itself have gone stale in the interim.
    PasswordStateResult? preconditionState,
    /// The [GithubBackupService] instance already authenticated during
    /// the precondition check — MUST be reused for the password-state
    /// publish step, not rebuilt. At the point where this function
    /// publishes the new shared state, `github_access_encrypted` is
    /// still encrypted under the OLD password (the code that
    /// re-encrypts it to the new password runs LATER, further down this
    /// same function). Building a fresh service by trying to decrypt
    /// that still-old-encrypted blob with `newPinHash` would always
    /// fail, making `service == null` guaranteed on every rotation, not
    /// just an edge case — this was a real, confirmed bug in an earlier
    /// version of this function. Reusing the already-authenticated
    /// instance sidesteps the ordering problem entirely, since it
    /// doesn't need to decrypt anything a second time.
    GithubBackupService? preconditionService,
    void Function(String status)? onProgress,
    Future<List<String>?> Function(BuildContext context)? onRequestMnemonic,
    void Function(bool success, bool githubOk)? onComplete,
  }) async {
    final settingsBox = Hive.box(_boxName);

    // Step 1: capture the OLD KDF parameter tier before anything else
    // changes. This is a snapshot, not a live reference — it cannot be
    // affected by anything this function does later, including writing
    // kdf_hardened in Step 4.
    final KdfParams oldParams = CryptoEngine.currentAuthParams();
    final KdfParams oldEncryptionParams =
        CryptoEngine.currentEncryptionParams();

    // Step 2: evaluate the device's CURRENT rooted status and compute
    // the NEW parameter tier that will become active once this rotation
    // completes — explicitly, from `rooted`, WITHOUT writing
    // kdf_hardened yet and without reading it back. This is exactly the
    // ({auth, encryption}) pair that Steps 3 onward will use.
    final bool rooted = await CryptoEngine.isDeviceRooted();
    final newTier = CryptoEngine.paramsForHardenedState(rooted);
    final KdfParams newAuthParams = newTier.auth;
    final KdfParams newEncryptionParams = newTier.encryption;

    // Step 3: derive the new password hash using the NEW auth params
    // explicitly — this is what verifyPin will need to match against
    // once kdf_hardened actually flips to `rooted` in Step 5. Deriving
    // this with the OLD params (what the previous version of this
    // function did, implicitly, via the live global) would silently
    // produce a hash that stops verifying the moment kdf_hardened changes.
    final Uint8List authSalt = CryptoEngine.extractAuthSalt(oldPinHash);
    final String newPinHash = await CryptoEngine.hashPinWithSaltUsingParams(
        newPassword, authSalt, newAuthParams);

    // Step 4: migrate every encrypted_note, decrypting each under the
    // OLD encryption params (matching how they were actually encrypted
    // before this rotation) and re-encrypting under the NEW encryption
    // params explicitly (matching what decryptProcess will expect once
    // kdf_hardened flips). Builds a complete replacement collection in
    // memory and commits it in a single Hive write, or changes nothing
    // at all if any note fails to decrypt. Only proceed to change the
    // active password if this succeeds.
    onProgress?.call('ENCRYPTING NOTES...');
    final bool notesMigrated = await ref.read(localDatabaseProvider.notifier).migrateEncryptedNotes(
          oldPinHash,
          newPinHash,
          oldParams: oldEncryptionParams,
          newParams: newEncryptionParams,
        );

    if (!notesMigrated) {
      if (onComplete != null) {
        onComplete(false, false);
      } else if (context.mounted) {
        _showStatusDialog(
          context,
          'PASSWORD CHANGE FAILED',
          'YOUR ENCRYPTED NOTES COULD NOT BE MIGRATED TO THE NEW PASSWORD. NOTHING WAS CHANGED — YOUR OLD PASSWORD IS STILL ACTIVE AND YOUR NOTES ARE UNTOUCHED.',
        );
      }
      return;
    }

    // Step 5: notes are confirmed migrated (already re-encrypted under
    // newEncryptionParams) and newPinHash (already derived under
    // newAuthParams) are both consistent with the tier we're about to
    // make live. Only now is it safe to flip kdf_hardened and commit the
    // new password — every value being written from this point on
    // already matches the tier kdf_hardened is about to declare active.
    onProgress?.call('UPDATING SECURITY...');
    await settingsBox.put('kdf_hardened', rooted);

    await settingsBox.put('system_crypto_pin', newPinHash);
    await settingsBox.put('last_active_crypto_pin_snapshot', newPinHash);

    final String? hwWrappedNewPin = await CryptoEngine.hardwareWrap(newPinHash,
        keyAlias: CryptoEngine.passwordKeyAlias);
    if (hwWrappedNewPin != null) {
      await settingsBox.put('hw_wrapped_pin', hwWrappedNewPin);
    } else {
      await settingsBox.delete('hw_wrapped_pin');
    }

    // Step 4 (moved earlier, before password-state publish — see below
    // for why): existing GitHub token / device-key rotation. Unchanged
    // in what it actually does; only its POSITION relative to the
    // password-state publish has moved, and its failures are tracked
    // instead of silently swallowed.
    //
    // WHY THIS RUNS BEFORE THE PASSWORD-STATE PUBLISH NOW: another
    // device only learns "the password changed" by observing a bumped
    // passwordGeneration in password_state.json. If that publish
    // happened BEFORE device_key.json was rewrapped for the new
    // password, a small but real window would exist where another
    // device could correctly detect staleness, correctly enter
    // recovery, correctly enter the new password + phrase, and still
    // fail — because the actual artifact recovery depends on
    // (device_key.json) wouldn't exist yet. Running this block first
    // means that by the time any other device could possibly observe
    // the new generation, device_key.json already reflects it.
    bool githubRotationOk = true;
    bool deviceKeyReadyForPublish = true;
    final String? accessBlob = settingsBox.get('github_access_encrypted');
    if (accessBlob != null) {
      try {
        final String? unwrappedForRead = await CryptoEngine.hardwareUnwrap(
            accessBlob,
            keyAlias: CryptoEngine.githubTokenKeyAlias);
        if (unwrappedForRead == null) {
          secureDebugLog(
              '[settings] hardwareUnwrap failed for githubTokenKeyAlias during password rotation - treating stored blob as software-encrypted only');
        }
        final String accessJson = await CryptoEngine.decryptProcessWithParams(
            unwrappedForRead ?? accessBlob, oldPinHash, oldEncryptionParams);
        if (accessJson != 'DECRYPTION FAULT') {
          final Map<String, dynamic> access = jsonDecode(accessJson);
          final String reEncrypted =
              await CryptoEngine.encryptProcessWithParams(
                  accessJson, newPinHash, newEncryptionParams);
          final String? hwWrapped = await CryptoEngine.hardwareWrap(reEncrypted,
              keyAlias: CryptoEngine.githubTokenKeyAlias);
          if (hwWrapped == null) {
            secureDebugLog(
                '[settings] hardwareWrap failed for githubTokenKeyAlias during password rotation re-save - falling back to software-encrypted storage only');
          }
          await settingsBox.put(
              'github_access_encrypted', hwWrapped ?? reEncrypted);

          if (!context.mounted) return;
          final List<String>? mnemonicWords = onRequestMnemonic != null
              ? await onRequestMnemonic(context)
              : await _promptMnemonicRecovery(context);
          if (mnemonicWords != null) {
            onProgress?.call('CONFIRMING...');
            final Map<String, String> rewrapped =
                await CryptoEngine.wrapDeviceKeyWithParams(
              authSaltBytes: authSalt,
              password: newPassword,
              mnemonicWords: mnemonicWords,
              params: newEncryptionParams,
            );

            try {
              final service = GithubBackupService(
                  token: access['token'], repoPath: access['repo']);
              await service.amendSync(
                  upsertFiles: {'device_key.json': jsonEncode(rewrapped)},
                  message: 'password rotation');
              await settingsBox.put('device_key_owned_repo', access['repo']);
            } catch (e) {
              githubRotationOk = false;
              deviceKeyReadyForPublish = false;
              secureDebugLog(
                  '[settings] device_key.json re-upload failed during password rotation: $e');
            }
          } else {
            // User declined the recovery-phrase step. This is not
            // treated as a githubRotationOk=false failure (the user
            // made a deliberate choice, not an error occurred) — but
            // device_key.json genuinely was NOT updated, so the
            // password-state publish below must still be held back:
            // publishing a new generation without a matching
            // device_key.json would leave any OTHER device unable to
            // complete recovery even with the correct new password.
            deviceKeyReadyForPublish = false;
            secureDebugLog(
                '[settings] user declined recovery-phrase re-entry during password rotation - device_key.json not updated, password-state publish will be held pending');
          }
        } else {
          githubRotationOk = false;
          deviceKeyReadyForPublish = false;
          secureDebugLog(
              '[settings] stored GitHub credentials failed to decrypt with the old password during rotation — GitHub token was not re-encrypted');
        }
      } catch (e) {
        githubRotationOk = false;
        deviceKeyReadyForPublish = false;
        secureDebugLog(
            '[settings] unexpected error re-encrypting GitHub credentials during password rotation: $e');
      }
    }

    // Publish the new shared password-generation state, if GitHub backup
    // is configured. Uses the REAL conditional write (fast-forward
    // check), not the force-push path used for notes.
    //
    // Only reached AFTER the block above, and only actually attempted
    // if deviceKeyReadyForPublish is true — see the comment on that
    // block for why publish must not run ahead of device_key.json.
    //
    // IMPORTANT: a rejected conditional write only proves the branch
    // moved since we read it — it does NOT by itself prove another
    // device changed the password. A completely unrelated commit (e.g.
    // this same device's own note sync, or another artifact entirely)
    // moving the branch would look identical from here. So a rejection
    // is treated the same as any other unconfirmed-write failure: mark
    // pending, then immediately re-fetch and classify what's actually
    // there — using the exact same logic as reconcilePendingPublish —
    // rather than assuming the worst (orphaned) from the rejection alone.
    //
    // In every outcome below, system_crypto_pin and the local notes have
    // ALREADY been committed above — this block only ever affects
    // whether the ACCOUNT-WIDE shared state and this device's own
    // bookkeeping reflect that change, never the local password itself.
    bool passwordStatePublished = true;
    if (preconditionState != null && !deviceKeyReadyForPublish) {
      // device_key.json isn't ready yet (user declined recovery-phrase
      // entry, or the upload itself failed) — hold back the generation
      // bump entirely rather than publish something other devices can't
      // actually use to recover. Marked pending so a LATER opportunity
      // (once the user completes recovery-phrase entry, or the upload
      // succeeds on a retry) can still publish correctly. This does NOT
      // attempt reconciliation immediately, unlike the failure path
      // below, since there is nothing to reconcile yet — this device
      // never even attempted a write.
      final int newGeneration = (preconditionState.remoteGeneration ??
              PasswordStateManager.getKnownGeneration()) +
          1;
      final String newChangeId = PasswordStateManager.generateChangeId();
      await PasswordStateManager.setPublishPending(
        pendingGeneration: newGeneration,
        pendingChangeId: newChangeId,
      );
      passwordStatePublished = false;
      secureDebugLog(
          '[settings] password-state publish held back - device_key.json is not yet ready for cross-device recovery. Marked pending.');
    } else if (preconditionState != null) {
      // device_key.json IS ready (or GitHub credentials weren't
      // configured at all in a way that required it) — safe to attempt
      // the actual publish now.
      final GithubBackupService? service = preconditionService;

      final int newGeneration = (preconditionState.remoteGeneration ??
              PasswordStateManager.getKnownGeneration()) +
          1;
      final String newChangeId = PasswordStateManager.generateChangeId();

      if (service == null) {
        // Could not even build a service to attempt the publish
        // (credentials missing, or failed to decrypt). This is NOT
        // success — no write was ever attempted, so this device's known
        // generation must not be silently advanced. Treated as an
        // ambiguous/pending failure, same as a network error.
        await PasswordStateManager.setPublishPending(
          pendingGeneration: newGeneration,
          pendingChangeId: newChangeId,
        );
        passwordStatePublished = false;
        secureDebugLog(
            '[settings] could not build GitHub service to publish password-state during rotation (credentials missing or undecryptable) - marked pending for reconciliation');
      } else {
        final String deviceId = PasswordStateManager.getOrCreateDeviceId();
        bool wroteSuccessfully = false;

        try {
          await PasswordStateManager.publishNewState(
            service: service,
            newGeneration: newGeneration,
            newChangeId: newChangeId,
            deviceId: deviceId,
            expectedParentSha: preconditionState.observedRefSha,
          );
          wroteSuccessfully = true;
        } catch (e) {
          // Covers BOTH GithubConditionalWriteConflict (branch moved —
          // for ANY reason, not necessarily another password change)
          // and ordinary network/timeout failures. Neither case lets us
          // conclude anything on its own; both require the classification
          // step below to find out what actually happened.
          secureDebugLog(
              '[settings] password-state publish did not confirm during rotation - will classify via immediate reconciliation: $e');
        }

        if (wroteSuccessfully) {
          await PasswordStateManager.recordKnownState(
            generation: newGeneration,
            changeId: newChangeId,
          );
        } else {
          // Mark pending, then immediately attempt reconciliation using
          // the SAME live connection — no need to wait for the next
          // app launch when we're already online right now.
          await PasswordStateManager.setPublishPending(
            pendingGeneration: newGeneration,
            pendingChangeId: newChangeId,
          );

          await PasswordStateManager.reconcilePendingPublish(service);

          // Read the resulting fields directly rather than trust a
          // single enum value — reconcilePendingPublish's own outcome
          // enum is for logging/diagnostics; the fields it left behind
          // are the actual source of truth for what settings.dart does
          // next.
          final bool stillPending = PasswordStateManager.isPublishPending();
          final bool nowOrphaned = LocalRotationOrphanStatus.isOrphaned();
          final bool matchesWhatWeWanted = !stillPending &&
              !nowOrphaned &&
              PasswordStateManager.getKnownGeneration() == newGeneration;

          passwordStatePublished = matchesWhatWeWanted;

          if (nowOrphaned) {
            secureDebugLog(
                '[settings] immediate reconciliation after rejected/failed publish confirmed another device won - local rotation is now orphaned');
          } else if (stillPending) {
            secureDebugLog(
                '[settings] immediate reconciliation after rejected/failed publish could not resolve the state yet - remains pending for a later attempt');
          } else if (matchesWhatWeWanted) {
            secureDebugLog(
                '[settings] immediate reconciliation confirmed this device\'s own write actually succeeded (or a retry landed it) - not orphaned, not pending');
          }
        }
      }
    }

    onProgress?.call('DONE');
    final bool isOrphaned = LocalRotationOrphanStatus.isOrphaned();
    final bool fullyOk = githubRotationOk && passwordStatePublished;
    if (onComplete != null) {
      onComplete(true, fullyOk);
    } else if (context.mounted) {
      if (fullyOk) {
        _showAcknowledgeDialog(context, 'PASSWORD UPDATED',
            'YOUR PASSWORD HAS BEEN CHANGED SUCCESSFULLY.');
      } else if (isOrphaned) {
        _showStatusDialog(
          context,
          'PASSWORD CHANGE CONFLICT',
          'YOUR PASSWORD WAS CHANGED ON THIS DEVICE, BUT ANOTHER DEVICE CHANGED IT AT THE SAME TIME AND ITS CHANGE WAS ACCEPTED FIRST. THIS DEVICE\'S NOTES ARE NOW ENCRYPTED WITH A PASSWORD THAT OTHER DEVICES DO NOT KNOW. THIS DEVICE CANNOT SYNC UNTIL YOU RESOLVE THIS — SEE RECOVERY.',
        );
      } else if (!passwordStatePublished) {
        _showStatusDialog(
          context,
          'PASSWORD UPDATED — SYNC STATE PENDING',
          'YOUR PASSWORD WAS CHANGED AND YOUR NOTES ARE SAFE, BUT THE SHARED PASSWORD-STATE COULD NOT BE CONFIRMED WITH GITHUB (LIKELY A CONNECTION ISSUE). THIS WILL BE RETRIED AUTOMATICALLY. OTHER DEVICES MAY NOT DETECT THIS CHANGE UNTIL THAT COMPLETES.',
        );
      } else {
        _showStatusDialog(
          context,
          'PASSWORD UPDATED — GITHUB SYNC NEEDS ATTENTION',
          'YOUR PASSWORD WAS CHANGED AND YOUR NOTES ARE SAFE, BUT YOUR STORED GITHUB CREDENTIALS COULD NOT BE FULLY RE-ENCRYPTED. RE-ENTER YOUR GITHUB TOKEN IN SETTINGS TO RESTORE SYNC.',
        );
      }
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
                    'SYSTEM DESTRUCTION WARNING',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'THIS PROCESS IS NOT REVERSIBLE. ALL ENCRYPTED FILES WILL BE PERMANENTLY REMOVED.',
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: theme.dialogBorderColor, width: 0.8),
                          ),
                          child: Text(
                            'NO',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF888888)
                                  : const Color(0xFF525252),
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
                          final targetsToPurge = currentItems
                              .where((item) => item.type == 'encrypted_note')
                              .toList();

                          for (var target in targetsToPurge) {
                            await ref
                                .read(localDatabaseProvider.notifier)
                                .deleteItem(target.id);
                          }

                          final settingsBox = Hive.box(_boxName);
                          await settingsBox.delete('system_crypto_pin');
                          await settingsBox
                              .delete('last_active_crypto_pin_snapshot');
                          await settingsBox.delete('github_access_encrypted');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 6),
                          decoration:
                              const BoxDecoration(color: Color(0xFFEF4444)),
                          child: const Text(
                            'YES',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
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
      _showStatusDialog(context, 'PASSWORD REQUIRED',
          'SET THE CRYPTOGRAPHY ACCESS PASSWORD FIRST BEFORE STORING A GITHUB TOKEN.');
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
      barrierDismissible: false,
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
                      border: Border.all(
                          color: theme.dialogBorderColor, width: 0.8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayHeaderTitle,
                          style: TextStyle(
                            color: (hasPinFailed || lockStringStatus != null)
                                ? const Color(0xFFEF4444)
                                : theme.textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.05,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Builder(builder: (context) {
                          Color currentFieldBorderColor;
                          if (hasPinFailed || lockStringStatus != null) {
                            currentFieldBorderColor = const Color(0xFFEF4444);
                          } else {
                            currentFieldBorderColor = theme.dialogBorderColor;
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: currentFieldBorderColor,
                                width:
                                    (hasPinFailed || lockStringStatus != null)
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
                                color:
                                    (hasPinFailed || lockStringStatus != null)
                                        ? const Color(0xFFEF4444)
                                        : theme.textMain,
                                fontSize: 16,
                                letterSpacing: 4,
                                fontWeight: FontWeight.bold,
                              ),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (hasPinFailed) hasPinFailed = false;
                                });
                              },
                              decoration: const InputDecoration(
                                  counterText: '',
                                  border: InputBorder.none,
                                  isDense: true),
                            ),
                          );
                        }),
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
                                        color: theme.dialogBorderColor,
                                        width: 0.8)),
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

                                final bool isPinValid = await CryptoEngine
                                    .verifyPinWithHardwareBinding(
                                        pinVerifyController.text, globalPin);

                                if (isPinValid) {
                                  final String rawPassword =
                                      pinVerifyController.text;
                                  await settingsBox.put(
                                      'secure_failed_attempts', 0);
                                  await settingsBox.put(
                                      'secure_lockout_until', 0);

                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  if (!screenContext.mounted) return;
                                  await _openGithubAccessDialog(
                                      screenContext, globalPin, rawPassword);
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
                                    await _purgeEncryptedNotesOnBruteForce();
                                    await settingsBox.put(
                                        'secure_failed_attempts', 0);
                                    await settingsBox.put(
                                        'secure_lockout_until', 0);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    if (!screenContext.mounted) return;
                                    _showAcknowledgeDialog(
                                        screenContext,
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
    ).then((_) => countdownTimer?.cancel());
  }

  /// Decrypts the stored GitHub credentials (if any) using the given
  /// current password hash, and returns a ready-to-use
  /// [GithubBackupService]. Returns null if no credentials are stored,
  /// or if they fail to decrypt with the given hash — callers should
  /// treat a null result the same as "GitHub isn't usably configured
  /// right now," not attempt to distinguish why.
  Future<GithubBackupService?> _buildGithubServiceFromStoredCredentials(
      String pinHash) async {
    final settingsBox = Hive.box(_boxName);
    final String? accessBlob = settingsBox.get('github_access_encrypted');
    if (accessBlob == null) return null;

    try {
      final String? unwrappedForRead = await CryptoEngine.hardwareUnwrap(
          accessBlob,
          keyAlias: CryptoEngine.githubTokenKeyAlias);
      final String decoded = await CryptoEngine.decryptProcess(
          unwrappedForRead ?? accessBlob, pinHash);
      if (decoded == 'DECRYPTION FAULT') return null;
      final Map<String, dynamic> access = jsonDecode(decoded);
      final String? token = access['token']?.toString();
      final String? repo = access['repo']?.toString();
      if (token == null || repo == null || token.isEmpty || repo.isEmpty) {
        return null;
      }
      return GithubBackupService(token: token, repoPath: repo);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openGithubAccessDialog(
      BuildContext context, String pinHash, String rawPassword) async {
    final settingsBox = Hive.box(_boxName);
    final String? accessBlob = settingsBox.get('github_access_encrypted');

    String initialToken = '';
    String initialRepo = '';

    if (accessBlob != null) {
      try {
        final String? unwrappedForRead = await CryptoEngine.hardwareUnwrap(
            accessBlob,
            keyAlias: CryptoEngine.githubTokenKeyAlias);
        if (unwrappedForRead == null) {
          secureDebugLog(
              '[settings] hardwareUnwrap failed for githubTokenKeyAlias while opening GitHub settings - treating stored blob as software-encrypted only');
        }
        final String decoded = await CryptoEngine.decryptProcess(
            unwrappedForRead ?? accessBlob, pinHash);
        final Map<String, dynamic> access = jsonDecode(decoded);
        initialToken = (access['token'] ?? '').toString();
        initialRepo = (access['repo'] ?? '').toString();
      } catch (_) {}
    }

    if (!context.mounted) return;
    _showGithubAccessDialog(context, pinHash, rawPassword,
        initialToken: initialToken, initialRepo: initialRepo);
  }

  void _showGithubAccessDialog(
      BuildContext context, String pinHash, String rawPassword,
      {String initialToken = '', String initialRepo = ''}) {
    final BuildContext screenContext = context;
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    final settingsBox = Hive.box(_boxName);

    final TextEditingController tokenController =
        TextEditingController(text: initialToken);
    final TextEditingController repoController =
        TextEditingController(text: initialRepo);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
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
                  border:
                      Border.all(color: theme.dialogBorderColor, width: 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GITHUB TOKEN STORE',
                      style: TextStyle(
                          color: theme.textMain,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.05),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: tokenController,
                      obscureText: true,
                      contextMenuBuilder: (context, state) =>
                          const SizedBox.shrink(),
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
                      contextMenuBuilder: (context, state) =>
                          const SizedBox.shrink(),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: theme.dialogBorderColor,
                                    width: 0.8)),
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
                            final String token = tokenController.text.trim();
                            final String repo = repoController.text.trim();

                            if (token.isEmpty || repo.isEmpty) {
                              Navigator.pop(context);
                              return;
                            }

                            Navigator.pop(context);
                            if (!screenContext.mounted) return;

                            // A tiny delay here matters: pushing a new
                            // dialog route in the same synchronous tick as
                            // popping the previous one can get the new
                            // route lost while the pop is still settling -
                            // this was why SAVING never appeared at all on
                            // some devices. Letting one frame pass first
                            // avoids the race.
                            await Future.delayed(Duration.zero);
                            if (!screenContext.mounted) return;

                            bool savingDialogVisible = true;
                            void closeSavingDialogIfOpen() {
                              if (savingDialogVisible &&
                                  screenContext.mounted) {
                                savingDialogVisible = false;
                                Navigator.of(screenContext, rootNavigator: true)
                                    .pop();
                              }
                            }

                            _showSavingIndicatorDialog(screenContext, isDark);

                            final String payload =
                                jsonEncode({'token': token, 'repo': repo});
                            final String encrypted =
                                await CryptoEngine.encryptProcess(
                                    payload, pinHash);
                            final String? hwWrapped =
                                await CryptoEngine.hardwareWrap(encrypted,
                                    keyAlias: CryptoEngine.githubTokenKeyAlias);
                            if (hwWrapped == null) {
                              secureDebugLog(
                                  '[settings] hardwareWrap failed for githubTokenKeyAlias during token save - falling back to software-encrypted storage only');
                            }
                            await settingsBox.put('github_access_encrypted',
                                hwWrapped ?? encrypted);

                            if (!screenContext.mounted) return;
                            await _handlePostSaveGithubSync(
                              screenContext,
                              token,
                              repo,
                              rawPassword,
                              pinHash,
                              pullAfterKeySetup: false,
                              onBeforeUserPrompt: closeSavingDialogIfOpen,
                            );
                            closeSavingDialogIfOpen();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: theme.textMain),
                            child: Text('CONFIRM',
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
    String currentPinHash, {
    bool isExplicitRestore = false,
    bool pullAfterKeySetup = true,
    VoidCallback? onBeforeUserPrompt,
  }) async {
    final service = GithubBackupService(token: token, repoPath: repo);
    final settingsBox = Hive.box(_boxName);

    final List<String> syncLog = [];
    void log(String msg) {
      syncLog.add(msg);
      secureDebugLog(msg);
    }

    Future<void> finish(String title) async {
      onBeforeUserPrompt?.call();
      if (isExplicitRestore && context.mounted) {
        _showDiagnosticLogDialog(context, title, syncLog);
      }
    }

    try {
      Map<String, dynamic>? existingDeviceKey;
      try {
        existingDeviceKey = await service.fetchNoteFile('device_key.json');
        log('device_key.json fetch: ${existingDeviceKey == null ? "NOT FOUND" : "FOUND"}');
      } catch (e) {
        log('device_key.json fetch THREW: $e');
        existingDeviceKey = null;
      }

      String effectivePinHash = currentPinHash;
      final String? ownedRepo = settingsBox.get('device_key_owned_repo');
      final bool ownsThisRepoKey = ownedRepo == repo;
      log('ownedRepo locally = "$ownedRepo", this repo = "$repo", ownsThisRepoKey = $ownsThisRepoKey');

      if (existingDeviceKey == null) {
        log('taking first-time-setup branch');
        final Uint8List authSalt = CryptoEngine.extractAuthSalt(currentPinHash);
        final List<String> mnemonicWords =
            await CryptoEngine.generateMnemonic();
        final Map<String, String> wrapped = await CryptoEngine.wrapDeviceKey(
          authSaltBytes: authSalt,
          password: rawPassword,
          mnemonicWords: mnemonicWords,
        );

        try {
          await service.amendSync(
            upsertFiles: {'device_key.json': jsonEncode(wrapped)},
            message: 'device key setup',
          );
          await settingsBox.put('device_key_owned_repo', repo);
          log('device_key.json push succeeded');
        } catch (e) {
          log('device_key.json push FAILED: $e');
        }

        if (context.mounted) {
          onBeforeUserPrompt?.call();
          await _showMnemonicDisplayDialog(context, mnemonicWords);
        }
      } else if (!ownsThisRepoKey) {
        log('taking recovery branch - prompting for 12 words');
        if (!context.mounted) {
          log('context unmounted before mnemonic prompt, aborting');
          return;
        }
        onBeforeUserPrompt?.call();
        final List<String>? recoveredWords =
            await _promptMnemonicRecovery(context);
        if (recoveredWords == null) {
          log('mnemonic dialog closed without submitting (cancelled or dismissed)');
          await finish('RECOVERY CANCELLED');
          return;
        }
        log('12 words submitted, attempting unwrap');

        final Uint8List? unwrapped = await CryptoEngine.unwrapDeviceKey(
          wrapSalt: (existingDeviceKey['wrapSalt'] ?? '').toString(),
          wrapNonce: (existingDeviceKey['wrapNonce'] ?? '').toString(),
          wrappedAuthSalt:
              (existingDeviceKey['wrappedAuthSalt'] ?? '').toString(),
          password: rawPassword,
          mnemonicWords: recoveredWords,
        );

        if (unwrapped == null) {
          log('unwrapDeviceKey returned null - password or mnemonic did not match this backup');
          await finish('RECOVERY FAILED');
          return;
        }

        effectivePinHash =
            await CryptoEngine.hashPinWithSalt(rawPassword, unwrapped);
        await settingsBox.put('system_crypto_pin', effectivePinHash);
        await settingsBox.put(
            'last_active_crypto_pin_snapshot', effectivePinHash);
        await settingsBox.put('device_key_owned_repo', repo);

        final String? hwWrappedRecoveredPin = await CryptoEngine.hardwareWrap(
            effectivePinHash,
            keyAlias: CryptoEngine.passwordKeyAlias);
        if (hwWrappedRecoveredPin != null) {
          await settingsBox.put('hw_wrapped_pin', hwWrappedRecoveredPin);
        } else {
          await settingsBox.delete('hw_wrapped_pin');
        }

        final String reEncryptedAccess = await CryptoEngine.encryptProcess(
          jsonEncode({'token': token, 'repo': repo}),
          effectivePinHash,
        );
        await settingsBox.put('github_access_encrypted', reEncryptedAccess);
        log('re-encrypted stored GitHub credentials under the recovered key');
        log('unwrap succeeded, local key updated');
      } else {
        log('this device already owns this repo key, skipping recovery');
      }

      if (!pullAfterKeySetup) {
        log('pullAfterKeySetup is false, stopping after key setup/recovery');
        onBeforeUserPrompt?.call();
        return;
      }

      List<String> filesToImport = [];
      try {
        filesToImport = await service.listNoteFiles();
        log('listNoteFiles returned: $filesToImport');
      } catch (e) {
        log('listNoteFiles THREW: $e');
        filesToImport = [];
      }
      filesToImport.remove('device_key.json');
      log('filesToImport after removing device_key.json: $filesToImport');

      if (filesToImport.isEmpty) {
        log('nothing to import, stopping');
        onBeforeUserPrompt?.call();
        if (isExplicitRestore && context.mounted) {
          _showAcknowledgeDialog(context, 'BACKUP SIGN-IN SUCCESSFUL',
              '0 NOTES FOUND IN THIS BACKUP.');
        }
        await finish('RESTORE RESULT');
        return;
      }

      final notifier = ref.read(localDatabaseProvider.notifier);
      final List<CaptureItem> currentBackedUpItems = ref
          .read(localDatabaseProvider)
          .where((item) => item.backupEnabled)
          .toList();
      log('deleting ${currentBackedUpItems.length} existing local backup-enabled notes first');
      for (final item in currentBackedUpItems) {
        await notifier.deleteItem(item.id);
      }
      await notifier.clearSyncQueue();

      int importedCount = 0;
      for (final fileName in filesToImport) {
        try {
          final Map<String, dynamic>? data =
              await service.fetchNoteFile(fileName);
          log('fetched "$fileName" -> ${data == null ? "NULL" : "OK"}');
          if (data == null) continue;

          final String salt = (data['salt'] ?? '').toString();
          final String nonce = (data['nonce'] ?? '').toString();
          final String cyphertext = (data['cyphertext'] ?? '').toString();
          final String title = fileName.endsWith('.json')
              ? fileName.substring(0, fileName.length - 5)
              : fileName;

          String content;
          String type;
          if (salt.isEmpty) {
            content = cyphertext;
            type = 'note';
            log('"$fileName" is plaintext, title="$title"');
          } else {
            final String merged =
                CryptoEngine.mergeFromBackup(salt, nonce, cyphertext);
            final String testDecrypt =
                await CryptoEngine.decryptProcess(merged, effectivePinHash);
            log('"$fileName" decrypt: ${testDecrypt == "DECRYPTION FAULT" ? "FAULT" : "OK"}');
            if (testDecrypt == 'DECRYPTION FAULT') continue;
            content = merged;
            type = 'encrypted_note';
          }

          final bool inserted = await notifier.insertItem(content, type,
              title: title, backupEnabled: true);
          log('insertItem "$title" -> $inserted');
          if (inserted) importedCount++;
        } catch (e) {
          log('exception processing "$fileName": $e');
          continue;
        }
      }

      log('done, importedCount=$importedCount');
      onBeforeUserPrompt?.call();
      if (context.mounted) {
        _showAcknowledgeDialog(context, 'RESTORE COMPLETE',
            'IMPORTED $importedCount NOTE(S) FROM BACKUP.');
      }
      await finish('RESTORE RESULT');
    } catch (e, stackTrace) {
      syncLog.add('UNCAUGHT EXCEPTION: $e');
      syncLog.add('STACK TRACE: $stackTrace');
      secureDebugLog('SYNC UNCAUGHT EXCEPTION: $e');
      secureDebugLog('$stackTrace');
      onBeforeUserPrompt?.call();
      if (isExplicitRestore && context.mounted) {
        _showDiagnosticLogDialog(context, 'SYNC ERROR', syncLog);
      }
    }
  }

  // Non-dismissible loading indicator shown while token/repo/recovery data
  // is actually being written to local storage and pushed to GitHub - the
  // whole point is that background tapping does nothing here, matching the
  // same protection as the rest of this setup flow.
  void _showSavingIndicatorDialog(BuildContext context, bool isDark) {
    final theme = SettingsUiTheme(isDark);

    showGeneralDialog(
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
                width: 240,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.dialogBg,
                  border:
                      Border.all(color: theme.dialogBorderColor, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: theme.textMain),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'SAVING...',
                      style: TextStyle(
                          color: theme.textMain,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.05),
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

  void _showDiagnosticLogDialog(
      BuildContext context, String title, List<String> log) {
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
              width: 330,
              constraints: const BoxConstraints(maxHeight: 480),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.dialogBg,
                border: Border.all(color: theme.dialogBorderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: theme.textMain,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.05)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        log.isEmpty ? 'NO LOG ENTRIES' : log.join('\n'),
                        style: TextStyle(
                            color: theme.textSub, fontSize: 10, height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: theme.textMain),
                      child: Text(
                        'CLOSE',
                        textAlign: TextAlign.center,
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
  }

  Future<void> _showMnemonicDisplayDialog(
      BuildContext context, List<String> words) async {
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
                  border:
                      Border.all(color: theme.dialogBorderColor, width: 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RECOVERY PHRASE',
                      style: TextStyle(
                          color: theme.textMain,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.05),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'WRITE THESE 12 WORDS DOWN ON PAPER OR A TRUSTED DEVICE. THEY WILL NEVER BE SHOWN AGAIN.',
                      style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          height: 1.4),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: theme.textMain),
                            child: Text(
                              'I HAVE WRITTEN THIS DOWN',
                              style: TextStyle(
                                  color: isDark ? Colors.black : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
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
            decoration: BoxDecoration(
                border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
            alignment: Alignment.center,
            child: Text(
              words[i],
              style: TextStyle(
                  color: theme.textMain,
                  fontSize: 9,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }),
    );
  }

  String? _checkMnemonicLockout(Box settingsBox) {
    final int lockoutUntil =
        settingsBox.get('mnemonic_lockout_until', defaultValue: 0);
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

    final List<TextEditingController> controllers =
        List.generate(12, (_) => TextEditingController());
    final List<FocusNode> focusNodes = List.generate(12, (_) => FocusNode());
    String? lockStringStatus = _checkMnemonicLockout(settingsBox);
    bool showValidationError = false;
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
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            ensureCountdownRunning(setDialogState);
            final bool locked = lockStringStatus != null;

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
                    width: 340,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.dialogBg,
                      border: Border.all(
                        color: showValidationError
                            ? const Color(0xFF5F0E0D)
                            : theme.dialogBorderColor,
                        width: showValidationError ? 1.4 : 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lockStringStatus ?? 'ENTER 12-WORD RECOVERY PHRASE',
                          style: TextStyle(
                            color: locked
                                ? const Color(0xFFEF4444)
                                : theme.textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.05,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _mnemonicFieldRow(
                          controllers.sublist(0, 6),
                          focusNodes.sublist(0, 6),
                          0,
                          theme,
                          setDialogState,
                          !locked,
                          onFieldEdited: () => showValidationError = false,
                        ),
                        const SizedBox(height: 8),
                        _mnemonicFieldRow(
                          controllers.sublist(6, 12),
                          focusNodes.sublist(6, 12),
                          6,
                          theme,
                          setDialogState,
                          !locked,
                          onFieldEdited: () => showValidationError = false,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            InkWell(
                              onTap: () => Navigator.pop(context, null),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                    border: Border.all(
                                        color: theme.dialogBorderColor,
                                        width: 0.8)),
                                child: Text(
                                  'CANCEL',
                                  style: TextStyle(
                                      color: isDark
                                          ? const Color(0xFF888888)
                                          : const Color(0xFF525252),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () async {
                                final activeLock =
                                    _checkMnemonicLockout(settingsBox);
                                if (activeLock != null) {
                                  setDialogState(
                                      () => lockStringStatus = activeLock);
                                  return;
                                }

                                final List<String> words = controllers
                                    .map((c) => c.text.trim().toLowerCase())
                                    .toList();
                                final bool allFilled =
                                    words.every((w) => w.isNotEmpty);
                                final bool allKnown = allFilled &&
                                    words.every((w) =>
                                        CryptoEngine.isValidMnemonicWord(w));
                                final bool checksumOk = allKnown &&
                                    await CryptoEngine.validateMnemonicChecksum(
                                        words);

                                if (checksumOk) {
                                  await settingsBox.put(
                                      'mnemonic_failed_attempts', 0);
                                  await settingsBox.put(
                                      'mnemonic_lockout_until', 0);
                                  if (!context.mounted) return;
                                  Navigator.pop(context, words);
                                } else {
                                  int attempts = settingsBox.get(
                                          'mnemonic_failed_attempts',
                                          defaultValue: 0) +
                                      1;
                                  await settingsBox.put(
                                      'mnemonic_failed_attempts', attempts);
                                  final int penalty =
                                      CryptoEngine.lockoutSecondsForAttempt(
                                          attempts);
                                  if (penalty > 0) {
                                    await settingsBox.put(
                                      'mnemonic_lockout_until',
                                      DateTime.now().millisecondsSinceEpoch +
                                          penalty * 1000,
                                    );
                                  }
                                  setDialogState(() {
                                    showValidationError = true;
                                    lockStringStatus =
                                        _checkMnemonicLockout(settingsBox);
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration:
                                    BoxDecoration(color: theme.textMain),
                                child: Text(
                                  'COMMIT',
                                  style: TextStyle(
                                      color:
                                          isDark ? Colors.black : Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
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
    for (final node in focusNodes) {
      node.dispose();
    }
    return result;
  }

  Widget _mnemonicFieldRow(
    List<TextEditingController> rowControllers,
    List<FocusNode> rowFocusNodes,
    int startIndex,
    SettingsUiTheme theme,
    void Function(void Function()) setDialogState,
    bool enabled, {
    required void Function() onFieldEdited,
  }) {
    return Row(
      children: List.generate(6, (i) {
        final TextEditingController controller = rowControllers[i];
        final FocusNode focusNode = rowFocusNodes[i];
        final String word = controller.text.trim().toLowerCase();
        final bool isUnknown =
            word.isNotEmpty && !CryptoEngine.isValidMnemonicWord(word);
        final int globalIndex = startIndex + i;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 5 ? 0 : 4),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              contextMenuBuilder: (context, state) => const SizedBox.shrink(),
              onChanged: (value) {
                onFieldEdited();
                if (value.contains(' ')) {
                  final String stripped = value.replaceAll(' ', '');
                  controller.text = stripped;
                  controller.selection =
                      TextSelection.collapsed(offset: stripped.length);
                  if (globalIndex < 11) {
                    focusNode.nextFocus();
                  } else {
                    focusNode.unfocus();
                  }
                }
                setDialogState(() {});
              },
              style: TextStyle(color: theme.textMain, fontSize: 10),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                hintText: '${startIndex + i + 1}',
                hintStyle: TextStyle(color: theme.textSub, fontSize: 9),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                      color: isUnknown
                          ? const Color(0xFF5F0E0D)
                          : theme.dialogBorderColor,
                      width: isUnknown ? 1.2 : 0.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                      color:
                          isUnknown ? const Color(0xFF5F0E0D) : theme.textMain,
                      width: 1.2),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _showSlidingPanel(
      BuildContext context, String title, List<Widget> children, bool isDark) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          final panelBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
          final textMain = isDark ? Colors.white : Colors.black;
          final borderColor =
              isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

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
                                        border: Border.all(
                                            color: borderColor, width: 0.8),
                                      ),
                                      child: Icon(Icons.arrow_back,
                                          size: 14, color: textMain),
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
                            Divider(
                                color: borderColor, height: 1, thickness: 0.8),
                            Expanded(
                              child: ListView(
                                physics: const ClampingScrollPhysics(),
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
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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
                    style: TextStyle(
                        color: textMain,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.03),
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

  Widget _buildInfoSection(
      String header, String body, Color textMain, Color textSub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: TextStyle(
                color: textMain,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.05),
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

  // Same strikethrough-grows-in animation as the to-do list's task
  // completion (Stack + TweenAnimationBuilder + ClipRect/widthFactor):
  // the red "unmet" label sits underneath permanently, and a green
  // strikethrough copy grows left-to-right over it as the rule becomes
  // satisfied, and shrinks back if the password changes and no longer
  // meets it.
  Widget _buildPasswordRequirementRow(String label, bool satisfied) {
    const unmetColor = Color(0xFFEF4444);
    const metColor = Color(0xFF22C55E);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('· ',
              style: TextStyle(
                  color: unmetColor, fontSize: 9, fontWeight: FontWeight.w500)),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      color: unmetColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.02),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: satisfied ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutQuart,
                  builder: (context, value, child) {
                    return ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: metColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.02,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: metColor,
                            decorationThickness: 1.4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          AnimatedScale(
            scale: satisfied ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: const Text('✓',
                style: TextStyle(
                    color: metColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
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
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          children: [
            Text(
              'SYSTEM SETTINGS',
              style: TextStyle(
                  color: theme.textMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.02),
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
                        style: TextStyle(
                            color: theme.textMain,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.05),
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
                        color: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFDDDDDD),
                        border: Border.all(
                            color: theme.mainBorderColor, width: 0.8),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 120),
                        alignment: isDark
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
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
              valueListenable:
                  Hive.box(_boxName).listenable(keys: ['system_crypto_pin']),
              builder: (context, Box box, _) {
                final String currentPin =
                    box.get('system_crypto_pin', defaultValue: '');

                return _buildMenuTile(
                  title: 'CRYPTOGRAPHIC ACCESS PASSWORD',
                  subtitle: currentPin.isEmpty
                      ? 'SETUP REQUIRED // SECURITY KEY'
                      : 'ACTIVE // MODIFY SECURE TERMINAL DEPLOYMENT KEY',
                  textMain: theme.textMain,
                  textSub: currentPin.isEmpty
                      ? const Color(0xFFEF4444)
                      : theme.textSub,
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
              valueListenable: Hive.box(_boxName)
                  .listenable(keys: ['github_access_encrypted']),
              builder: (context, Box box, _) {
                final bool githubReady =
                    box.get('github_access_encrypted') != null;

                return _buildMenuTile(
                  title: 'GITHUB TOKEN STORE',
                  subtitle: githubReady
                      ? 'ACTIVE // MODIFY REPOSITORY BACKUP CREDENTIALS'
                      : 'SETUP REQUIRED // FINE-GRAINED TOKEN + REPOSITORY',
                  textMain: theme.textMain,
                  textSub:
                      githubReady ? theme.textSub : const Color(0xFFEF4444),
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
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.02),
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
                              border: Border.all(
                                  color: theme.mainBorderColor, width: 0.8),
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'EXPORT BACKUP',
                              style: TextStyle(
                                  color: isDark ? Colors.black : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.02),
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
                              border:
                                  Border.all(color: theme.textMain, width: 0.8),
                              color: Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'RESTORE BACKUP',
                              style: TextStyle(
                                  color: theme.textMain,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.02),
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
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '02 // GATEWAY LAYER (SPLASH SCREEN)',
                      'Handles high-performance layout warm-ups during frame construction phases. Intercepts the primary platform loading sequence, executing an isolated 2-second linear opacity rendering track (Fade -> Visual Suspension -> Purge) that seamlessly aligns the system layout context with your previous light or dark UI settings to eradicate aggressive boot-flash anomalies completely.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '03 // STRUCTURAL HUB NAVIGATION',
                      'A streamlined typography-focused matrix navigation track that maps layout views safely. Built with absolute override layout parameters that dictate viewport allocation during active software keyboard states. Instead of forcing physical view compression or breaking cross-axis element alignments, incoming OS input windows act as smooth layer overlays.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '04 // MATRIX TIMELINE COMPONENT',
                      'Renders a massive, low-fatigue 13-column structural layout tracking 365 daily block elements simultaneously. Darkened tracking indicators pinpoint precise historical data allocation slots, while empty slots define exact leftover capacity indexes inside the current runtime period.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '05 // QUICKNOTE SANDBOX MODULE',
                      'Employs an anti-collapse scrolling viewport configuration tied directly to explicit layout boundaries and custom constraints. This forces live character generation streams to dynamically recalculate remaining box space when virtual keyboards arise, keeping active text editing targets completely visible.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '06 // INTERFACE REGULATION CONTROLS',
                      'Executes direct UI inversions via a streamlined state-toggle mechanism. Connects configuration panels into hardware-accelerated right-to-left slide transitions locked at a precise 1.0 width factor constraint. Sub-sheets completely obscure underlying layers, eliminating unnecessary drop-shadow re-renders to maximize device refresh rates.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '07 // DATA IMPORT/EXPORT SYSTEM',
                      'Features custom serialization engines that loop through application states, converting model entries into raw standardized JSON bytes. Built-in file picking mechanics handle direct filesystem interaction to securely transfer data without utilizing external cloud proxies or intermediate networks.',
                      theme.textMain,
                      theme.textSub),
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
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '02 // BOX CONTAINER MATRIX',
                      'Data storage blocks are separated into dedicated, context-isolated data compartments called "Boxes" (e.g., rocen_captures_box). Structural indexes replace classic relational tables, creating lightweight data access pathways that protect historical databases from schema breaking risks when fields expand.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '03 // MEMORY-FIRST BUFFER PIPELINE',
                      'Data structures are loaded straight into fast active RAM buffers during bootup. Read tasks operate directly inside this memory layer with zero disk latency. Create, update, and delete actions instantly change the cache array for direct visual updates, then stream down onto device hardware storage asynchronously.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '04 // CORRUPTION REPAIR FAILSAFE',
                      'A custom try-catch validation engine checks the integrity of database boxes during initialization. If a database interruption (like a sudden power drop) compromises data syntax, the broken data block is instantly isolated to prevent system boot loops, and initialized safely back to standard parameters.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '05 // APPLICATION PERMISSIONS OUTLINE',
                      'The application manifest explicitly excludes unnecessary network communication channels, background telemetry monitors, and analytical scrapers. Your information is physically unable to leave the system via background connection bridges.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '06 // CRYPTOGRAPHIC KEY WRAPPING',
                      'Activating the CRYPTOGRAPHIC ACCESS PASSWORD applies an isolated user verification requirement. Secure components (like encrypted_note parameters) evaluate this key matching verification block locally. Changing or deleting the security password immediately purges corresponding key-dependent items from storage to guarantee absolute protection against physical file manipulation.',
                      theme.textMain,
                      theme.textSub),
                  _buildInfoSection(
                      '07 // OFF-GRID FILE EXPORT UTILITY',
                      'Backup operations run on standard local UTF-8 data conversion engines. Generated data is written to user-designated folders via a native document explorer pipeline. Raw schema text is never transmitted through background trackers or third-party data processing endpoints.',
                      theme.textMain,
                      theme.textSub),
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
              onTap: () async {
                final bool rooted = await CryptoEngine.isDeviceRooted();
                final String hwTier = await CryptoEngine.hardwareKeyTier();
                if (!context.mounted) return;
                _showSlidingPanel(
                  context,
                  'PRIVACY POLICY',
                  [
                    _buildInfoSection(
                        '01 // APPLICATION DESCRIPTION',
                        'Rocen is a hyper-focused minimalist system blueprint designed to run high-utility tools without backend software bloat or visual clutter.',
                        theme.textMain,
                        theme.textSub),
                    _buildInfoSection(
                        '02 // SYSTEM AUTHORSHIP',
                        'Engineered and assembled by Darshseraphic.',
                        theme.textMain,
                        theme.textSub),
                    _buildInfoSection(
                        '03 // PURPOSE & DESIGN METHODOLOGY',
                        'Built to mitigate screen fatigue through a stark brutalist interface style, intentional whitespace, and highly structured typographic layouts.',
                        theme.textMain,
                        theme.textSub),
                    _buildInfoSection(
                        '04 // DEVELOPMENT TIMELINE MATRIX',
                        'Initial core system conceptualization, wireframing, and final architecture completion finalized over a highly compressed 24-hour rapid development sprint.',
                        theme.textMain,
                        theme.textSub),
                    _buildInfoSection(
                        '05 // ABSOLUTE ZERO DATA ACCUMULATION',
                        'This framework operates with a strict zero-telemetry policy. There are no analytics packages, usage tracking monitors, or remote crash trackers written into the codebase. No usage data, behavior, or metadata is ever collected, transmitted, or accessible to the developer, under any circumstance.',
                        theme.textMain,
                        theme.textSub),
                    _buildInfoSection(
                        '06 // ZERO-KNOWLEDGE NETWORK ARCHITECTURE',
                        'This application is not air-gapped. A single network channel exists, used exclusively to synchronize AES-256-GCM encrypted data with a GitHub repository you own and control, over a certificate-pinned connection. No server operated by this application\'s developer ever receives, stores, or has access to your data or credentials. Disabling backup removes this channel entirely, returning the application to fully local, offline operation.',
                        theme.textMain,
                        theme.textSub),
                    _buildInfoSection(
                        '07 // USER-OWNED STORAGE ARCHITECTURE',
                        'You retain absolute, exclusive ownership of your data files. The system cannot read, change, or access stored items outside its specific offline database context. Deleting the application instantly wipes all local cache directories from internal storage arrays.',
                        theme.textMain,
                        theme.textSub),
                    if (hwTier != 'strongbox')
                      _buildInfoSection(
                          '08 // STRONGBOX OR TEE SUPPORT',
                          'StrongBox security is not supported on this device. App security has transitioned to the Trusted Execution Environment (TEE).',
                          theme.textMain,
                          theme.textSub),
                    if (rooted)
                      _buildInfoSection(
                          '09 // DEVICE INTEGRITY NOTICE',
                          'THIS DEVICE APPEARS TO BE ROOTED OR MODIFIED. STANDARD OPERATING SYSTEM PROTECTIONS MAY NOT FULLY APPLY. TO COMPENSATE, THE APPLICATION HAS AUTOMATICALLY INCREASED ITS ENCRYPTION STRENGTH FOR THIS DEVICE. NO FEATURES ARE RESTRICTED.',
                          theme.textMain,
                          theme.textSub),
                  ],
                  isDark,
                );
              },
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
                'BUILD BY DARSHSERAPHIC',
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