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
    final String text = _noteController.text.trim();
    if (text.isNotEmpty) {
      ref.read(localDatabaseProvider.notifier).insertMultipleItems([text], 'note');
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
                      hintText: 'FIRST LINE IS TITLE...\nSUBSEQUENT LINES ARE DETAILS...',
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
                      InkWell(
                        onTap: _saveNote,
                        splashColor: splashColor,
                        highlightColor: splashColor,
                        hoverColor: hoverColor,
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

          // RESTORED OLD UI RECORDS LIST
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

                final List<String> lines = item.content.split('\n');
                final String title = lines.first.trim();
                final String description = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';

                // Re-implemented old structured panel block layout
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: containerBg,
                    border: Border.all(color: borderColor, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Bar Block containing the Title & Trash action
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                title.toUpperCase(),
                                style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.02),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => ref.read(localDatabaseProvider.notifier).deleteItem(item.id),
                              behavior: HitTestBehavior.opaque,
                              child: Icon(
                                Icons.delete_outline,
                                color: textSub,
                                size: 22, // Retained: Noticeable trash size adjustment
                              ),
                            )
                          ],
                        ),
                      ),
                      // Details Body Block (Only rendered if subsequent lines exist)
                      if (description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            description,
                            style: TextStyle(color: textMain, fontSize: 13, height: 1.45),
                          ),
                        ),
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