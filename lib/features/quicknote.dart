import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../main.dart';

class QuickNoteScreen extends ConsumerStatefulWidget {
  const QuickNoteScreen({super.key});

  @override
  ConsumerState<QuickNoteScreen> createState() => _QuickNoteScreenState();
}

class _QuickNoteScreenState extends ConsumerState<QuickNoteScreen> {
  final TextEditingController _noteController = TextEditingController();

  void _saveNote() {
    if (_noteController.text.trim().isNotEmpty) {
      ref.read(localDatabaseProvider.notifier).addItem(_noteController.text, 'note');
      _noteController.clear();
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'note').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final containerBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEEEEEE);

    // FIXED: Strict high-contrast color values for the click interactions
    final splashColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06);
    final hoverColor = isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICKNOTE REGISTRY',
            style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
          ),
          const SizedBox(height: 16),

          // INPUT MODULE
          Container(
            decoration: BoxDecoration(
              color: containerBg,
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Column(
              children: [
                Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      cursorColor: textMain,
                      selectionColor: textMain.withOpacity(0.15),
                      selectionHandleColor: textMain,
                    ),
                  ),
                  child: TextField(
                    controller: _noteController,
                    maxLines: 4,
                    style: TextStyle(color: textMain, fontSize: 13, height: 1.4),
                    decoration: InputDecoration(
                      hintText: 'WRITE CRITICAL LOGS HERE...',
                      hintStyle: TextStyle(color: textSub, fontSize: 12, letterSpacing: 0.05),
                      contentPadding: const EdgeInsets.all(16),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: borderColor, width: 0.8)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // FIXED: Forced CustomBorder configuration to eliminate violet circle artifact
                      InkWell(
                        onTap: _saveNote,
                        splashColor: splashColor,
                        highlightColor: splashColor,
                        hoverColor: hoverColor,
                        // 👈 This forces the splash and highlight shapes to remain perfectly square
                        customBorder: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Text(
                            'COMMIT',
                            style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.05),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),

          Divider(color: borderColor, height: 32, thickness: 0.8),

          // PERSISTED RECORDS LIST
          Expanded(
            child: items.isEmpty
                ? Center(
              child: Text(
                'NO ENTRIES LOGGED',
                style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05),
              ),
            )
                : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: containerBg,
                    border: Border.all(color: borderColor, width: 0.8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.content,
                          style: TextStyle(color: textMain, fontSize: 13, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => ref.read(localDatabaseProvider.notifier).deleteItem(item.id),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.delete_outline,
                            color: textSub,
                            size: 18,
                          ),
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}