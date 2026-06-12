import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../core/database.dart';
import '../main.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const String _boxName = 'rocen_settings_box';

  // CORE LAUNCH ENGINE FOR OUTWARD LINKS
  Future<void> _launchWebsiteUrl() async {
    final Uri url = Uri.parse('https://rocen.lovable.app/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('System Error: Could not execute route handshake to $url');
    }
  }

  // SYSTEM ENGINE FOR OUTWARD FEEDBACK REDIRECT PIPELINE
  Future<void> _launchFeedbackUrl() async {
    final Uri url = Uri.parse('https://rocen.lovable.app/feedback');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('System Error: Could not execute route handshake to $url');
    }
  }

  // ==========================================
  // CUSTOM HIGH-CONTRAST STATUS NOTIFICATION DIALOG
  // ==========================================
  void _showStatusDialog(BuildContext context, String title, String message) {
    final isDark = ref.read(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    // Theme Inverted Configurations for the Center CTA Button
    final buttonBg = isDark ? Colors.white : Colors.black;
    final buttonText = isDark ? Colors.black : Colors.white;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.85),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dialogBg,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMain, fontSize: 11, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
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

  // ==========================================
  // DATA MANAGEMENT PERSISTENCE ENGINES
  // ==========================================
  Future<void> _handleDataExport() async {
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

  void _showImportWarningDialog(BuildContext context) {
    final isDark = ref.read(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.8),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 310,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dialogBg,
                border: Border.all(color: borderColor, width: 0.8),
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
                    style: TextStyle(color: textMain, fontSize: 11.5, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
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
                            border: Border.all(color: borderColor, width: 0.8),
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

  // ==========================================
  // FLOW 1 & 2: 6-DIGIT PIN CREATION ENGINE
  // ==========================================
  void _showCreatePinDialog(BuildContext context, {String initialValue = ''}) {
    final isDark = ref.read(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    final TextEditingController pinController = TextEditingController(text: initialValue);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.75),
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
                    color: dialogBg,
                    border: Border.all(color: borderColor, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SETUP CRYPTOGRAPHY PIN',
                        style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                      ),
                      const SizedBox(height: 20),

                      Stack(
                        children: [
                          Opacity(
                            opacity: 0.0,
                            child: TextField(
                              controller: pinController,
                              keyboardType: TextInputType.number,
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
                                    ? textMain
                                    : (isFilled ? textMain.withOpacity(0.6) : borderColor);

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
                                    style: TextStyle(color: textMain, fontSize: 10),
                                  ),
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
                                border: Border.all(color: borderColor, width: 0.8),
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
                            onTap: pinController.text.length < 6
                                ? null
                                : () {
                              final typedPin = pinController.text;
                              Navigator.pop(context);
                              _showAreYouSureDialog(context, typedPin);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: pinController.text.length == 6 ? textMain : textMain.withOpacity(0.2),
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

  // ==========================================
  // FLOW 2: DOUBLE-CHECK MUTATION INTERCEPTOR
  // ==========================================
  void _showAreYouSureDialog(BuildContext context, String typedPin) {
    final isDark = ref.read(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.75),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 290,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dialogBg,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SECURITY VERIFICATION',
                    style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ARE YOU SURE TO ADD THIS PASSWORD?',
                    style: TextStyle(color: textMain, fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
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
                            border: Border.all(color: borderColor, width: 0.8),
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

                          final settingsBox = Hive.box(_boxName);
                          await settingsBox.put('system_crypto_pin', typedPin);
                          await settingsBox.put('last_active_crypto_pin_snapshot', typedPin);

                          if (context.mounted) {
                            _showForgotWarningDialog(context);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: textMain),
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

  // ==========================================
  // FLOW 3: LOST ACCESS PIPELINE ADVISORY
  // ==========================================
  void _showForgotWarningDialog(BuildContext context) {
    final isDark = ref.read(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.75),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dialogBg,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CRITICAL NOTICE',
                    style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'IF YOU FORGOT THE PASSWORD YOU HAVE TO TAP THE CLEAR',
                    style: TextStyle(color: textMain, fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(color: textMain),
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

  // ==========================================
  // FLOW 4: IRREVERSIBLE PURGE CONFIRMATION
  // ==========================================
  void _showClearConfirmationDialog(BuildContext context) {
    final isDark = ref.read(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.8),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 310,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dialogBg,
                border: Border.all(color: borderColor, width: 0.8),
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
                    style: TextStyle(color: textMain, fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.02),
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
                            border: Border.all(color: borderColor, width: 0.8),
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

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final containerBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEEEEEE);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          children: [
            Text(
              'SYSTEM SETTINGS',
              style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
            ),
            const SizedBox(height: 24),

            // SYSTEM-WIDE DARK THEME CONFIG
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: containerBg,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DARK INTERFACE',
                        style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.05),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toggle system-wide dark mode',
                        style: TextStyle(color: textSub, fontSize: 10),
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
                        border: Border.all(color: borderColor, width: 0.8),
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

            // CRYPTOGRAPHIC ACCESS PIN INTERACTIVE CONTROLLER
            ValueListenableBuilder(
              valueListenable: Hive.box(_boxName).listenable(keys: ['system_crypto_pin']),
              builder: (context, Box box, _) {
                final String currentPin = box.get('system_crypto_pin', defaultValue: '');

                return _buildMenuTile(
                  title: 'CRYPTOGRAPHIC ACCESS PIN',
                  subtitle: currentPin.isEmpty
                      ? 'SETUP REQUIRED // 6-DIGIT SECURITY KEY'
                      : 'ACTIVE // MODIFY SECURE TERMINAL DEPLOYMENT KEY',
                  textMain: textMain,
                  textSub: currentPin.isEmpty ? const Color(0xFFEF4444) : textSub,
                  borderColor: borderColor,
                  onTap: () {
                    if (currentPin.isEmpty) {
                      _showCreatePinDialog(context);
                    } else {
                      _showClearConfirmationDialog(context);
                    }
                  },
                );
              },
            ),

            const SizedBox(height: 12),

            // ==========================================
            // HARMONIZED DATA WORKSPACE UTILITIES BLOCK
            // ==========================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black : Colors.white,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DATA UTILITIES',
                    style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.02),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Export or restore persistent application database matrices safely.',
                    style: TextStyle(color: textSub, fontSize: 10.5),
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
                              border: Border.all(color: borderColor, width: 0.8),
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
                          onTap: () => _showImportWarningDialog(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: textMain, width: 0.8),
                              color: Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'RESTORE BACKUP',
                              style: TextStyle(color: textMain, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.02),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            Divider(color: borderColor, thickness: 0.8),

            // [01] USER GUIDE
            _buildMenuTile(
              title: 'USER GUIDE',
              subtitle: 'Overview of system infrastructure panels',
              textMain: textMain,
              textSub: textSub,
              borderColor: borderColor,
              onTap: () => _showSlidingPanel(
                context,
                'USER GUIDE',
                [
                  _buildInfoSection(
                      '01 // SYSTEM ROOT ENGINE',
                      'Initializes global asynchronous reactive state loops using Riverpod. It maps runtime dependencies directly upon app activation and tracks low-level mutations securely. Bypasses persistent disk hangs via strict corruption validation parameters, completely ensuring zero structural app freezing or unhandled memory loops.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '02 // GATEWAY LAYER (SPLASH SCREEN)',
                      'Handles high-performance layout warm-ups during frame construction phases. Intercepts the primary platform loading sequence, executing an isolated 2-second linear opacity rendering track (Fade -> Visual Suspension -> Purge) that seamlessly aligns the system layout context with your previous light or dark UI settings to eradicate aggressive boot-flash anomalies completely.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '03 // STRUCTURAL HUB NAVIGATION',
                      'A streamlined typography-focused matrix navigation track that maps layout views safely. Built with absolute override layout parameters that dictate viewport allocation during active software keyboard states. Instead of forcing physical view compression or breaking cross-axis element alignments, incoming OS input windows act as smooth layer overlays.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '04 // MATRIX TIMELINE COMPONENT',
                      'Renders a massive, low-fatigue 13-column structural layout tracking 365 daily block elements simultaneously. Darkened tracking indicators pinpoint precise historical data allocation slots, while empty slots define exact leftover capacity indexes inside the current runtime period.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '05 // QUICKNOTE SANDBOX MODULE',
                      'Employs an anti-collapse scrolling viewport configuration tied directly to explicit layout boundaries and custom constraints. This forces live character generation streams to dynamically recalculate remaining box space when virtual keyboards arise, keeping active text editing targets completely visible.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '06 // INTERFACE REGULATION CONTROLS',
                      'Executes direct UI inversions via a streamlined state-toggle mechanism. Connects configuration panels into hardware-accelerated right-to-left slide transitions locked at a precise 1.0 width factor constraint. Sub-sheets completely obscure underlying layers, eliminating unnecessary drop-shadow re-renders to maximize device refresh rates.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '07 // DATA IMPORT/EXPORT SYSTEM',
                      'Features custom serialization engines that loop through application states, converting model entries into raw standardized JSON bytes. Built-in file picking mechanics handle direct filesystem interaction to securely transfer data without utilizing external cloud proxies or intermediate networks.',
                      textMain, textSub
                  ),
                ],
                isDark,
              ),
            ),

            // [02] DATA SECURITY
            _buildMenuTile(
              title: 'DATA SECURITY',
              subtitle: 'Information encryption & local cache schemas',
              textMain: textMain,
              textSub: textSub,
              borderColor: borderColor,
              onTap: () => _showSlidingPanel(
                context,
                'DATA SECURITY',
                [
                  _buildInfoSection(
                      '01 // STORAGE PIPELINE (NOSQL ENGINE)',
                      'Rocen avoids slow, heavy relational SQL frameworks entirely. The application operates exclusively on a lightning-fast NoSQL key-value architecture powered by Hive. Text strings and file indicators are encoded directly into raw binary streams written inside dedicated sandbox partitions allocated to the app hardware space.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '02 // BOX CONTAINER MATRIX',
                      'Data storage blocks are separated into dedicated, context-isolated data compartments called "Boxes" (e.g., rocen_captures_box). Structural indexes replace classic relational tables, creating lightweight data access pathways that protect historical databases from schema breaking risks when fields expand.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '03 // MEMORY-FIRST BUFFER PIPELINE',
                      'Data structures are loaded straight into fast active RAM buffers during bootup. Read tasks operate directly inside this memory layer with zero disk latency. Create, update, and delete actions instantly change the cache array for direct visual updates, then stream down onto device hardware storage asynchronously.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '04 // CORRUPTION REPAIR FAILSAFE',
                      'A custom try-catch validation engine checks the integrity of database boxes during initialization. If a database interruption (like a sudden power drop) compromises data syntax, the broken data block is instantly isolated to prevent system boot loops, and initialized safely back to standard parameters.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '05 // APPLICATION PERMISSIONS OUTLINE',
                      'The application manifest explicitly excludes unnecessary network communication channels, background telemetry monitors, and analytical scrapers. Your information is physically unable to leave the system via background connection bridges.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '06 // CRYPTOGRAPHIC KEY WRAPPING',
                      'Activating the CRYPTOGRAPHIC ACCESS PIN applies an isolated user verification requirement. Secure components (like encrypted_note parameters) evaluate this key matching verification block locally. Changing or deleting the security PIN immediately purges corresponding key-dependent items from storage to guarantee absolute protection against physical file manipulation.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '07 // OFF-GRID FILE EXPORT UTILITY',
                      'Backup operations run on standard local UTF-8 data conversion engines. Generated data is written to user-designated folders via a native document explorer pipeline. Raw schema text is never transmitted through background trackers or third-party data processing endpoints.',
                      textMain, textSub
                  ),
                ],
                isDark,
              ),
            ),

            // [03] PRIVACY POLICY
            _buildMenuTile(
              title: 'PRIVACY POLICY',
              subtitle: 'Application definitions and core manifest details',
              textMain: textMain,
              textSub: textSub,
              borderColor: borderColor,
              onTap: () => _showSlidingPanel(
                context,
                'PRIVACY POLICY',
                [
                  _buildInfoSection(
                      '01 // APPLICATION DESCRIPTION',
                      'Rocen is a hyper-focused minimalist system blueprint designed to run high-utility tools without backend software bloat or visual clutter.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '02 // SYSTEM AUTHORSHIP',
                      'Engineered and assembled by Darshseraphic.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '03 // PURPOSE & DESIGN METHODOLOGY',
                      'Built to mitigate screen fatigue through a stark brutalist interface style, intentional whitespace, and highly structured typographic layouts.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '04 // DEVELOPMENT TIMELINE MATRIX',
                      'Initial core system conceptualization, wireframing, and final architecture completion finalized over a highly compressed 24-hour rapid development sprint.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '05 // ABSOLUTE ZERO DATA ACCUMULATION',
                      'This framework operates with a strict zero-telemetry policy. There are no analytics packages, usage tracking monitors, remote crash trackers, or cloud-based data bridges written into the codebase. All workspace activity remains strictly contained on your local device.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '06 // AIR-GAPPED HARDWARE ISOLATION',
                      'The application runs entirely within an air-gapped system methodology. Without network permissions or server communication layers configured in its structural layer, user interactions are kept private, secure, and permanently anchored inside the isolated sandbox space of your hardware.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '07 // USER-OWNED STORAGE ARCHITECTURE',
                      'You retain absolute, exclusive ownership of your data files. The system cannot read, change, or access stored items outside its specific offline database context. Deleting the application instantly wipes all local cache directories from internal storage arrays.',
                      textMain, textSub
                  ),
                ],
                isDark,
              ),
            ),

            // [04] WEBSITE
            _buildMenuTile(
              title: 'WEBSITE',
              subtitle: 'Access outward system project portals',
              textMain: textMain,
              textSub: textSub,
              borderColor: borderColor,
              onTap: _launchWebsiteUrl,
            ),

            // [05] FEEDBACK
            _buildMenuTile(
              title: 'FEEDBACK',
              subtitle: 'Report pipeline anomalies or system logs',
              textMain: textMain,
              textSub: textSub,
              borderColor: borderColor,
              onTap: _launchFeedbackUrl,
            ),

            const SizedBox(height: 48),

            // THE SYSTEM SIGNATURE STAMP
            Center(
              child: Text(
                'BUILD BY DARSHSERPHIC',
                style: TextStyle(
                  color: textSub.withOpacity(0.5),
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