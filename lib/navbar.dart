import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'features/bookmarks.dart';
import 'features/quicknote.dart';
import 'features/voicenote.dart';
import 'features/clipboard.dart';
import 'features/ideainbox.dart';
import 'main.dart'; // Imported to access themeProvider

enum CaptureModule {
  quickNote('NOTE', QuickNoteScreen()),
  voiceNote('VOICE', VoiceNoteScreen()),
  clipboard('CLIP', ClipboardScreen()),
  bookmark('BOOK', BookmarksScreen()),
  ideaInbox('IDEA', IdeaInboxScreen());

  final String label;
  final Widget screen;
  const CaptureModule(this.label, this.screen);
}

final navigationProvider = StateProvider<CaptureModule>((ref) => CaptureModule.quickNote);

class MinimalNavbar extends ConsumerWidget {
  const MinimalNavbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeModule = ref.watch(navigationProvider);
    final isDark = ref.watch(themeProvider); // Listening to theme changes

    // Clean rule border tweak for Light vs Dark theme
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: borderColor, width: 0.8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: CaptureModule.values.map((module) {
          final isSelected = activeModule == module;

          // Dynamic color logic based on selection state AND theme architecture
          final textColor = isDark
              ? (isSelected ? Colors.white : const Color(0xFFCCCCCC))
              : (isSelected ? Colors.black : const Color(0xFF4D4D4D));

          return GestureDetector(
            onTap: () => ref.read(navigationProvider.notifier).state = module,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Text(
                module.label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: 0.05,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}