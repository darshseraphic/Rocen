import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // CUSTOM ROUTE BUILDER FOR THE RIGHT-TO-LEFT SMOOTH TAB SLIDE EFFECT (NO SHADOWS)
  void _showSlidingPanel(BuildContext context, String title, List<Widget> children, bool isDark) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          final panelBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
          final textMain = isDark ? Colors.white : Colors.black;
          final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
          final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

          return Scaffold(
            // Removed opacity/shadow background tint for a perfectly clean entry
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
                    widthFactor: 0.85,
                    heightFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: panelBg,
                        border: Border(left: BorderSide(color: borderColor, width: 1.0)),
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

                            // SCROLLABLE BODY LOGIC
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

  // FACTORY METHOD FOR REUSABLE STRUCTURAL SYSTEM TILES
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
  Widget build(BuildContext context, WidgetRef ref) {
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

            // DARK MODE SETTING CARD CONTAINER
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
                  _buildInfoSection('MATRIX TIMELINE TAB', 'Displays a fixed 13-column calendar matrix tracking all 365 days of the year simultaneously. Filled cells reflect elapsed time; open cells reveal year runtime remaining.', textMain, textSub),
                  _buildInfoSection('NOTES DECK MODULE', 'An integrated sandbox allowing frictionless capturing of plaintext headers and structured layout variables instantly.', textMain, textSub),
                  _buildInfoSection('THEME REGULATION', 'Dynamic high-contrast color values override interface attributes instantly with inversion controls.', textMain, textSub),
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
                  _buildInfoSection('STORAGE PIPELINE', '100% of internal state configurations and notes data map locally straight onto device storage blocks. No server handshakes occur.', textMain, textSub),
                  _buildInfoSection('PERMISSIONS OUTLINE', 'Network tracking access and dynamic cross-application telemetry bridges are entirely omitted from compile manifests.', textMain, textSub),
                  _buildInfoSection('IMAGE FETCHING LAYER', 'Asset buffers and media paths resolve entirely on hardware caches, fetching indices cleanly from isolated device paths without mirror processes.', textMain, textSub),
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
                  _buildInfoSection('APPLICATION DESCRIPTION', 'Rocen is an integrated, low-fi brutalist system blueprint built to run high-utility tools without backend pollution or network bloat.', textMain, textSub),
                  _buildInfoSection('SYSTEM AUTHOR', 'Developed entirely by Darshvici.', textMain, textSub),
                  _buildInfoSection('PURPOSE & NEED', 'Engineered to defeat visual fatigue by utilizing stark, clean interfaces and intentional data layouts.', textMain, textSub),
                  _buildInfoSection('DEVELOPMENT MATRIX', 'Initial platform conceptualization to complete assembly overhaul completed in a pure 24-hour rapid deployment sequence.', textMain, textSub),
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
              onTap: () => _showComingSoonDialog(context, 'PROJECT PORTAL WEBPAGE', isDark),
            ),

            // [05] FEEDBACK
            _buildMenuTile(
              title: 'FEEDBACK',
              subtitle: 'Report pipeline anomalies or system logs',
              textMain: textMain,
              textSub: textSub,
              borderColor: borderColor,
              onTap: () => _showComingSoonDialog(context, 'FEEDBACK PIPELINE INTERFACE', isDark),
            ),
          ],
        ),
      ),
    );
  }
}