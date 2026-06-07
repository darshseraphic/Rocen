import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // >>> ADD THIS NEW METHOD HERE <<<
  // SYSTEM ENGINE FOR OUTWARD FEEDBACK REDIRECT PIPELINE
  Future<void> _launchFeedbackUrl() async {
    final Uri url = Uri.parse('https://rocen.lovable.app/feedback');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('System Error: Could not execute route handshake to $url');
    }
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

                      // SEGMENTED HOOK ARCHITECTURE MATCHING QUICKNOTE
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
                              // Interface Gone (Dismiss current entry view)
                              Navigator.pop(context);
                              // Trigger Confirmation Stage
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
                          // Re-route processing array directly back to password workspace engine
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
                            // Instantly chain sequence to structural requirement 3
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
                        onTap: () => Navigator.pop(context), // Undo the process cleanly
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
                          Navigator.pop(context); // Clear configuration warning overlay

                          // Execution Block: Pull and isolate local data arrays
                          final currentItems = ref.read(localDatabaseProvider);
                          final targetsToPurge = currentItems.where((item) => item.type == 'encrypted_note').toList();

                          // Execute full sequential physical workspace reference sweep
                          for (var target in targetsToPurge) {
                            await ref.read(localDatabaseProvider.notifier).deleteItem(target.id);
                          }

                          // Clear keys from global preferences
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

  // CUSTOM ROUTE BUILDER FOR THE RIGHT-TO-LEFT SMOOTH TAB SLIDE EFFECT (100% FULL PAGE)
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
                            // PANEL HEADER BACK NAVIGATION TAB
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

                            // SCROLLABLE PANEL CONTENT BLOCK
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

  // MINIMAL UTILITY BUILDER FOR COMING SOON PROMPTS
  void _showComingSoonDialog(BuildContext context, String featureTitle, bool isDark) {
    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0F0F0F) : Colors.white;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: dialogBg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SYSTEM STATUS',
                style: TextStyle(color: textSub, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.05),
              ),
              const SizedBox(height: 8),
              Text(
                '$featureTitle IS COMING SOON',
                style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: -0.01),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: textMain,
                    ),
                    child: Text(
                      'ACKNOWLEDGE',
                      style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // REUSABLE STRUCTURAL TILES FACTORY
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
            style: TextStyle(color: textSub, fontSize: 11, height: 1.4),
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
                      'Initializes state tracking and dynamic configuration variables via Riverpod. Sets up persistent disk storage boxes via Hive locally with absolute zero background network pollution or tracker threads. Contains an active corruption bypass pipeline to prevent app thread hangs.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '02 // GATEWAY LAYER (SPLASH SCREEN)',
                      'Intercepts platform load phases. Executes a sequential 2-second opacity mapping (Fade-In -> Visual Hold -> Fade-Out) that updates background hexes to light or dark instantly depending on your previous system selection to kill boot flashes. Destroys itself from device memory once done.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '03 // STRUCTURAL HUB NAVIGATION',
                      'A minimal, low-fatigue typography navigation track managing screen selections. Enforces absolute scaffold layout parameter overrides that allow keyboard assemblies to slide in cleanly as structural overlays instead of physically compressing navigation bars or breaking view alignments.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '04 // MATRIX TIMELINE COMPONENT',
                      'Renders an expansive 13-column structural timeline array mapping out all 365 calendar segments simultaneously. Shaded block indicators illustrate elapsed timelines, while open blocks map operational capacity limits left in the active calendar phase.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '05 // QUICKNOTE SANDBOX MODULE',
                      'Features an advanced anti-collapse text scroll viewport framework (using explicit Expanded boundaries and SingleChildScrollView parameters). This forces text input metrics to dynamically scale and stay safely visible inside remaining boundaries when system keyboards push bottom navigation paths up.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '06 // INTERFACE REGULATION CONTROLS',
                      'Manages immediate UI inversion variables. Hooks sub-sheets into dedicated right-to-left animation pipelines locked at a 1.0 width Factor constraint to seamlessly map panels across 100% of the display boundaries, blocking out background layouts and dropping heavy dropshadow rendering tasks completely.',
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
                      'Rocen bypasses heavy, slow relational SQL frameworks completely. The system utilizes a lightweight NoSQL key-value database engine called Hive. Data maps directly into flat binary blocks written strictly onto internal device hardware partitions. Cloud synchronization pipelines, servers, and telemetry relays are 100% omitted from the application code.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '02 // BOX CONTAINER MATRIX',
                      'Instead of complex relational SQL tables, records are organized into isolated data compartments called "Boxes" (e.g., system_settings). Rows and columns are replaced by lightning-fast, schemaless key-value indexes. This allows seamless framework growth without the threat of database schema crashes.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '03 // MEMORY-FIRST PIPELINE',
                      'To optimize interface speed, boxes are buffered entirely inside the device\'s active RAM memory on boot. Queries and data reads execute with absolute zero disk delay. Writes update the memory registry instantly for immediate UI rendering, then lazily flush the changes down to physical binary disk partitions in the background.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '04 // CORRUPTION REPAIR FAILSAFE',
                      'If a data commit sequence gets interrupted (such as a sudden device shutdown), a custom try-catch engine monitors the handshake during the next boot phase. If file corruption is detected, the broken block is instantly isolated, purged from the disk, and a fresh data box is initialized to safeguard the core application runtime.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '05 // APPLICATION PERMISSIONS OUTLINE',
                      'Network traffic tracking descriptors, background web scraping handshakes, and third-party tracking assets are strictly excluded from compile manifests to preserve full data isolation.',
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
                      'Rocen is an integrated, low-fi brutalist system blueprint built to run high-utility tools without backend pollution or network bloat.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '02 // SYSTEM AUTHOR',
                      'Developed entirely by Darshseraohic.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '03 // PURPOSE & NEED',
                      'Engineered to defeat visual fatigue by utilizing stark, clean interfaces and intentional data layouts.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '04 // DEVELOPMENT MATRIX',
                      'Initial platform conceptualization to complete assembly overhaul completed in a pure 24-hour rapid deployment sequence.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '05 // ABSOLUTE ZERO DATA COLLECTION',
                      'The workspace architecture maintains a strict zero-collection manifest. The source framework is built with no telemetry tracking scripts, analytical tokens, crash report transmitters, or third-party background scraper threads. User data never leaves your hardware.',
                      textMain, textSub
                  ),
                  _buildInfoSection(
                      '06 // AIR-GAPPED NETWORK ISOLATION',
                      'Rocen operates under a complete air-gapped data methodology. Because no network permission structures or communication handlers are compiled into the operational database layer, user inputs are strictly safe, immutable, and 100% locked within the offline secure sandbox directory of the local device.',
                      textMain, textSub
                  ),
                ],
                isDark,
              ),
            ),

            // [04] WEBSITE - WIRED UP DIRECTLY TO YOUR WEB PORTAL
            _buildMenuTile(
              title: 'WEBSITE',
              subtitle: 'Access outward system project portals',
              textMain: textMain,
              textSub: textSub,
              borderColor: borderColor,
              onTap: _launchWebsiteUrl,
            ),
// [05] FEEDBACK - RE-ROUTED DIRECTLY TO YOUR SECURE URL ENDPOINT
            _buildMenuTile(
              title: 'FEEDBACK',
              subtitle: 'Report pipeline anomalies or system logs',
              textMain: textMain,
              textSub: textSub,
              borderColor: borderColor,
              onTap: _launchFeedbackUrl, // <-- Point directly to the new launcher function
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