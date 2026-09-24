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
import '../core/master_key_local_store.dart';
import '../core/master_key_production_service.dart';
import '../core/password_key_derivation.dart';
import '../core/github_backup_service.dart';
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
      secureDebugLog('External route launch failed.');
    }
  }

  Future<void> _launchFeedbackUrl() async {
    final Uri url = Uri.parse('https://rocen.lovable.app/feedback');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      secureDebugLog('External route launch failed.');
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
                        fontWeight: FontWeight.normal,
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
                        fontWeight: FontWeight.normal,
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

  Future<void> _handleDataExport() async {
    if (!mounted) return;
    _showStatusDialog(
      context,
      'EXPORT UNAVAILABLE',
      'PROTECTED WORKSPACE EXPORT IS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE IS IMPLEMENTED. ROCEN WILL NOT EXPORT PLAINTEXT OR TEMPORARY CIPHERTEXT.',
    );
  }

  Future<void> _handleDataImport() async {
    if (!mounted) return;
    _showStatusDialog(
      context,
      'IMPORT UNAVAILABLE',
      'PROTECTED WORKSPACE IMPORT IS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE IS IMPLEMENTED. ROCEN WILL NOT PERSIST PLAINTEXT OR TEMPORARY CIPHERTEXT.',
    );
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
    _promptGithubAccessChallenge(context, isRestore: true);
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
                        fontWeight: FontWeight.normal,
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
                  selectionColor: theme.textMain.withValues(alpha: 0.2),
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
                                      : theme.textMain.withValues(alpha: 0.2),
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
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, anim1, anim2) {
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
                  Text('SECURITY VERIFICATION', style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text('ARE YOU SURE YOU WANT TO SET THIS PASSWORD?', style: TextStyle(color: theme.textMain, fontSize: 12, height: 1.5)),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _showCreatePinDialog(context, initialValue: typedPin);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
                          child: Text('CANCEL', style: TextStyle(color: isDark ? const Color(0xFF888888) : const Color(0xFF525252), fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          try {
                            final List<String> mnemonic = await CryptoEngine.generateMnemonic();
                            await MasterKeyProductionService.instance.establishFirstDevice(
                              password: typedPin,
                              mnemonicWords: mnemonic,
                            );
                            if (!context.mounted) return;
                            await _showMnemonicDisplayDialog(context, mnemonic);
                            if (context.mounted) {
                              _showAcknowledgeDialog(
                                context,
                                'CRYPTOGRAPHY READY',
                                'ONE RANDOM MASTER KEY IS NOW THE LOCAL DATASET AUTHORITY. STORE YOUR 12-WORD RECOVERY PHRASE SAFELY.',
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              _showStatusDialog(
                                context,
                                'CRYPTOGRAPHY SETUP FAILED',
                                'Rocen could not establish the local Master Key authority. NO REPLACEMENT MASTER KEY WAS CREATED.',
                              );
                            }
                          }
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
        );
      },
    );
  }

  void _promptChangePasswordChallenge(BuildContext context) {
    final BuildContext screenContext = context;
    final settingsBox = Hive.box(_boxName);
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    final TextEditingController controller = TextEditingController();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, anim1, anim2) {
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
                children: [
                  Text('ENTER CURRENT PASSWORD', style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    maxLength: 32,
                    autofocus: true,
                    decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          final String raw = controller.text;
                          final MasterKeyLocalRecord? record = await MasterKeyLocalStore.read();
                          final bool valid = record != null && await PasswordKeyDerivation.verifyPassword(raw, record.passwordVerifier);
                          if (!valid) {
                            await settingsBox.put('secure_failed_attempts', settingsBox.get('secure_failed_attempts', defaultValue: 0) + 1);
                            if (screenContext.mounted) {
                              _showStatusDialog(screenContext, 'PASSWORD VERIFICATION FAILED', 'THE PASSWORD DID NOT MATCH THE LOCAL VERIFIER. NO MASTER KEY WAS CHANGED.');
                            }
                            return;
                          }
                          await settingsBox.put('secure_failed_attempts', 0);
                          await settingsBox.put('secure_lockout_until', 0);
                          if (!dialogContext.mounted || !screenContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (screenContext.mounted) {
                            _showNewPasswordDialog(screenContext, raw);
                          }
                        },
                        child: const Text('VERIFY'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) => controller.dispose());
  }

  void _showNewPasswordDialog(BuildContext context, String rawOldPassword) {
    final BuildContext screenContext = context;
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    final TextEditingController controller = TextEditingController();
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, anim1, anim2) {
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
                children: [
                  Text('ENTER NEW PASSWORD', style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    maxLength: 32,
                    autofocus: true,
                    onChanged: (_) {},
                    decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                  ),
                  const SizedBox(height: 12),
                  ...CryptoEngine.passwordRequirementStatus(controller.text).map((s) => _buildPasswordRequirementRow(s.$1, s.$2)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          final String next = controller.text;
                          if (!CryptoEngine.isPasswordComplexityValid(next)) return;
                          Navigator.pop(dialogContext);
                          if (!screenContext.mounted) return;
                          await _runPasswordChangeWithProgressModal(screenContext, rawOldPassword, next);
                        },
                        child: const Text('CONFIRM'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) => controller.dispose());
  }

  Future<void> _runPasswordChangeWithProgressModal(
    BuildContext screenContext,
    String rawOldPassword,
    String newPassword,
  ) async {
    final isDark = ref.read(themeProvider);
    final List<TextEditingController> controllers = List.generate(12, (_) => TextEditingController());
    final List<FocusNode> focusNodes = List.generate(12, (_) => FocusNode());
    final settingsBox = Hive.box(_boxName);
    List<String>? mnemonic;

    await showGeneralDialog<void>(
      context: screenContext,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, anim1, anim2) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 340,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SettingsUiTheme(isDark).dialogBg,
                    border: Border.all(color: SettingsUiTheme(isDark).dialogBorderColor, width: 0.8),
                  ),
                  child: _buildMnemonicEntryState(
                    SettingsUiTheme(isDark),
                    isDark,
                    controllers,
                    focusNodes,
                    null,
                    false,
                    setState,
                    settingsBox,
                    onCancel: () => Navigator.pop(dialogContext),
                    onSubmit: (words) async {
                      mnemonic = words;
                      Navigator.pop(dialogContext);
                    },
                    onValidationError: () => setState(() {}),
                    onFieldEdited: () => setState(() {}),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    for (final c in controllers) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
    if (!screenContext.mounted || mnemonic == null) return;

    try {
      await _executePasswordChange(
        screenContext,
        rawOldPassword,
        newPassword,
        mnemonicWords: mnemonic!,
      );
    } catch (_) {
      if (screenContext.mounted) {
        _showStatusDialog(screenContext, 'PASSWORD CHANGE FAILED', 'THE SAME MASTER KEY COULD NOT BE REWRAPPED UNDER THE NEW PASSWORD. NO REPLACEMENT MASTER KEY WAS CREATED.');
      }
    }
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
          controllers.sublist(0, 3),
          focusNodes.sublist(0, 3),
          0,
          theme,
          setDialogState,
          !locked,
          onFieldEdited: onFieldEdited,
        ),
        const SizedBox(height: 8),
        _mnemonicFieldRow(
          controllers.sublist(3, 6),
          focusNodes.sublist(3, 6),
          3,
          theme,
          setDialogState,
          !locked,
          onFieldEdited: onFieldEdited,
        ),
        const SizedBox(height: 8),
        _mnemonicFieldRow(
          controllers.sublist(6, 9),
          focusNodes.sublist(6, 9),
          6,
          theme,
          setDialogState,
          !locked,
          onFieldEdited: onFieldEdited,
        ),
        const SizedBox(height: 8),
        _mnemonicFieldRow(
          controllers.sublist(9, 12),
          focusNodes.sublist(9, 12),
          9,
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
    String rawOldPassword,
    String newPassword, {
    required List<String> mnemonicWords,
  }) async {
    await MasterKeyProductionService.instance.changePassword(
      oldPassword: rawOldPassword,
      newPassword: newPassword,
      mnemonicWords: mnemonicWords,
    );
    final MasterKeyLocalRecord? record = await MasterKeyLocalStore.read();
    if (record == null) {
      throw StateError('local Master Key record disappeared after password change');
    }

    // The new Recovery wrapper is durable locally immediately. Remote
    // publication is deliberately not hidden behind a plaintext token store;
    // the next GitHub setup/association supplies the token explicitly.
    if (context.mounted) {
      _showAcknowledgeDialog(
        context,
        'PASSWORD UPDATED',
        record.remoteRecoveryStatus == RemoteRecoveryStatus.unpublished
            ? 'THE PASSWORD CHANGED WITHOUT RE-ENCRYPTING NOTES. YOUR SAME MASTER KEY, NEK, AND TEK REMAIN THE DATASET KEYS. RE-OPEN GITHUB SETTINGS TO PUBLISH THE NEW RECOVERY WRAPPER.'
            : 'THE PASSWORD CHANGED WITHOUT RE-ENCRYPTING APPLICATION DATA.',
      );
    }
  }

  void _promptGithubAccessChallenge(
    BuildContext context, {
    bool isRestore = false,
  }) {
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    final controller = TextEditingController();
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, anim1, anim2) {
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
                children: [
                  Text('ENTER PASSWORD', style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(controller: controller, obscureText: true, maxLength: 32, autofocus: true, decoration: const InputDecoration(counterText: '', border: InputBorder.none)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
                      TextButton(
                        onPressed: () async {
                          final raw = controller.text;
                          final record = await MasterKeyLocalStore.read();
                          if (record == null || !await PasswordKeyDerivation.verifyPassword(raw, record.passwordVerifier)) {
                            if (context.mounted) _showStatusDialog(context, 'PASSWORD VERIFICATION FAILED', 'THE PASSWORD DID NOT MATCH THE LOCAL VERIFIER.');
                            return;
                          }
                          if (!dialogContext.mounted || !context.mounted) return;
                          Navigator.pop(dialogContext);
                          if (context.mounted) {
                            _showGithubAccessDialog(context, raw, isRestore: isRestore);
                          }
                        },
                        child: const Text('VERIFY'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) => controller.dispose());
  }

  GithubBackupService _buildGithubService({
    required String token,
    required String repoPath,
  }) {
    try {
      return GithubBackupService(token: token, repoPath: repoPath);
    } on StateError catch (e) {
      throw GithubSyncException(
          'GITHUB SECURITY CONFIGURATION IS INCOMPLETE: ${e.message}');
    }
  }

  void _showGithubAccessDialog(
      BuildContext context, String rawPassword, {bool isRestore = false}) {
    final BuildContext screenContext = context;
    final isDark = ref.read(themeProvider);
    final theme = SettingsUiTheme(isDark);
    final tokenController = TextEditingController();
    final repoController = TextEditingController(
      text: Hive.box(_boxName).get('github_repo')?.toString() ?? '',
    );
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, anim1, anim2) {
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
                children: [
                  Text('GITHUB ACCESS', style: TextStyle(color: theme.textMain, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(controller: tokenController, obscureText: true, contextMenuBuilder: (context, state) => const SizedBox.shrink(), decoration: const InputDecoration(hintText: 'Fine-grained token', border: InputBorder.none)),
                  const Divider(),
                  TextField(controller: repoController, decoration: const InputDecoration(hintText: 'Repository (username/repo)', border: InputBorder.none)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
                      TextButton(
                        onPressed: () async {
                          final token = tokenController.text.trim();
                          final repo = repoController.text.trim();
                          if (token.isEmpty || repo.isEmpty) return;
                          Navigator.pop(dialogContext);
                          if (!screenContext.mounted) return;
                          await _handlePostSaveGithubSync(
                            screenContext,
                            token,
                            repo,
                            rawPassword,
                            isExplicitRestore: isRestore,
                          );
                        },
                        child: const Text('CONFIRM'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      tokenController.dispose();
      repoController.dispose();
    });
  }

  Future<bool> _handlePostSaveGithubSync(
    BuildContext context,
    String token,
    String repo,
    String rawPassword, {
    bool isExplicitRestore = false,
  }) async {
    try {
      final service = _buildGithubService(token: token, repoPath: repo);
      await service.validateRepositoryAccess();

      final MasterKeyLocalRecord? local = await MasterKeyLocalStore.read();
      if (local == null) {
        final remote = await service.fetchNoteFile('device_key.json');
        if (remote == null) {
          if (context.mounted) {
            _showStatusDialog(context, 'GITHUB SETUP BLOCKED', 'ESTABLISH THE LOCAL MASTER KEY AUTHORITY BEFORE CONNECTING A NEW REPOSITORY.');
          }
          return false;
        }
        if (!context.mounted) return false;
        final words = await _promptMnemonicRecovery(context);
        if (words == null) return false;
        await MasterKeyProductionService.instance.recoverFromRemote(
          service: service,
          password: rawPassword,
          mnemonicWords: words,
          repository: repo,
          knownRecoveryWrapJson: jsonEncode(remote),
        );
      } else {
        final Map<String, dynamic>? remote =
            await service.fetchNoteFile('device_key.json');
        List<String> words = const <String>[];
        if (remote != null &&
            (local.remoteRecoveryStatus ==
                    RemoteRecoveryStatus.unpublished ||
                jsonEncode(remote) != local.recoveryWrap)) {
          if (!context.mounted) return false;
          final entered = await _promptMnemonicRecovery(context);
          if (entered == null) return false;
          words = entered;
        }
        await MasterKeyProductionService.instance.associateRemote(
          service: service,
          password: rawPassword,
          mnemonicWords: words,
          repository: repo,
        );
      }

      await Hive.box(_boxName).put('github_repo', repo);

      if (context.mounted) {
        _showAcknowledgeDialog(
          context,
          isExplicitRestore ? 'RECOVERY COMPLETE' : 'GITHUB LINKED',
          "THE SELECTED REPOSITORY NOW REFERENCES THIS DATASET'S RECOVERY-WRAPPED MASTER KEY. GITHUB TOKENS ARE NOT PERSISTED BY THE BLOCK B CUTOVER.",
        );
      }
      return true;
    } catch (_) {
      if (context.mounted) {
        _showStatusDialog(
          context,
          'GITHUB SETUP FAILED',
          'THE REPOSITORY COULD NOT BE ASSOCIATED WITH THIS DATASET. NO REPLACEMENT MASTER KEY WAS CREATED.',
        );
      }
      return false;
    }
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
                    _buildMnemonicWordRow(words.sublist(0, 3), theme),
                    const SizedBox(height: 8),
                    _buildMnemonicWordRow(words.sublist(3, 6), theme),
                    const SizedBox(height: 8),
                    _buildMnemonicWordRow(words.sublist(6, 9), theme),
                    const SizedBox(height: 8),
                    _buildMnemonicWordRow(words.sublist(9, 12), theme),
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
      children: List.generate(3, (i) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 2 ? 0 : 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                border: Border.all(color: theme.dialogBorderColor, width: 0.8)),
            alignment: Alignment.center,
            child: Text(
              words[i],
              style: TextStyle(
                  color: theme.textMain,
                  fontSize: 12,
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
      if (lockStringStatus == null) {
        return;
      }
      if (countdownTimer != null && countdownTimer!.isActive) return;
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final String? current = _checkMnemonicLockout(settingsBox);
        setState_(() {
          lockStringStatus = current;
        });
        if (current == null) {
          timer.cancel();
        }
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
                  selectionColor: theme.textMain.withValues(alpha: 0.2),
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
                          controllers.sublist(0, 3),
                          focusNodes.sublist(0, 3),
                          0,
                          theme,
                          setDialogState,
                          !locked,
                          onFieldEdited: () => showValidationError = false,
                        ),
                        const SizedBox(height: 8),
                        _mnemonicFieldRow(
                          controllers.sublist(3, 6),
                          focusNodes.sublist(3, 6),
                          3,
                          theme,
                          setDialogState,
                          !locked,
                          onFieldEdited: () => showValidationError = false,
                        ),
                        const SizedBox(height: 8),
                        _mnemonicFieldRow(
                          controllers.sublist(6, 9),
                          focusNodes.sublist(6, 9),
                          6,
                          theme,
                          setDialogState,
                          !locked,
                          onFieldEdited: () => showValidationError = false,
                        ),
                        const SizedBox(height: 8),
                        _mnemonicFieldRow(
                          controllers.sublist(9, 12),
                          focusNodes.sublist(9, 12),
                          9,
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
      children: List.generate(3, (i) {
        final TextEditingController controller = rowControllers[i];
        final FocusNode focusNode = rowFocusNodes[i];
        final String word = controller.text.trim().toLowerCase();
        final bool isUnknown =
            word.isNotEmpty && !CryptoEngine.isValidMnemonicWord(word);
        final int globalIndex = startIndex + i;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 2 ? 0 : 4),
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
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
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
                  Hive.box(_boxName).listenable(keys: ['master_key_record_v1']),
              builder: (context, Box box, _) {
                final bool authorityEstablished =
                    box.get('master_key_record_v1') != null;

                return _buildMenuTile(
                  title: 'CRYPTOGRAPHIC ACCESS PASSWORD',
                  subtitle: authorityEstablished
                      ? 'ACTIVE // MASTER KEY AUTHORITY ESTABLISHED'
                      : 'SETUP REQUIRED // MASTER KEY AUTHORITY',
                  textMain: theme.textMain,
                  textSub: authorityEstablished
                      ? theme.textSub
                      : const Color(0xFFEF4444),
                  borderColor: theme.mainBorderColor,
                  onTap: () {
                    if (!authorityEstablished) {
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
                  .listenable(keys: ['master_key_record_v1', 'github_repo']),
              builder: (context, Box box, _) {
                final bool githubReady = box.get('github_repo') != null;

                return _buildMenuTile(
                  title: 'GITHUB ACCESS',
                  subtitle: githubReady
                      ? 'ACTIVE // RE-ENTER TOKEN OR CHANGE REPOSITORY'
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
                      'The CRYPTOGRAPHIC ACCESS PASSWORD authenticates access to one random dataset Master Key. The password verifier authenticates only; a Password-KEK and Recovery-KEK wrap the same Master Key. Notes and GitHub token encryption are derived from that Master Key through the frozen Stage 4 HKDF hierarchy.',
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
                  color: theme.textSub.withValues(alpha: 0.5),
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
