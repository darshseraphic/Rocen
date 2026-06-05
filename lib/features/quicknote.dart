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
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _bodyController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _showDeleteConfirmation(BuildContext context, String id) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, anim1, anim2) {
        return Consumer(
          builder: (context, ref, child) {
            final isDark = ref.watch(themeProvider);
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF121212) : Colors.white,
                    border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5), width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text('PURGE THIS DATA SEGMENT?',
                            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.02)),
                      ),
                      Container(height: 0.8, color: isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5)),
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
                          Container(width: 0.8, height: 40, color: isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5)),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                ref.read(localDatabaseProvider.notifier).deleteItem(id);
                                Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'note').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    final ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QUICK NOTES', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 16),

          Flexible(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title Input Block
                  TextField(
                    controller: _titleController,
                    style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.w600),
                    cursorColor: textMain,
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: TextStyle(color: textSub, fontWeight: FontWeight.w400),
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.only(bottom: 8), // Adjusted slightly for breathing room
                    ),
                  ),

                  // 1px Horizontal Line Insertion
                  Container(
                    height: 1.0,
                    color: const Color(0xFFa6a6a6),
                  ),
                  const SizedBox(height: 8), // Padding before the body text block

                  // Body Story Input Block
                  TextField(
                    controller: _bodyController,
                    style: TextStyle(color: textMain, fontSize: 13),
                    maxLines: null,
                    cursorColor: textMain,
                    decoration: InputDecoration(
                      hintText: 'Tell me your story',
                      hintStyle: TextStyle(color: textSub),
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        if (_bodyController.text.trim().isNotEmpty) {
                          ref.read(localDatabaseProvider.notifier).insertItem(
                            _bodyController.text.trim(),
                            'note',
                            title: _titleController.text.trim(),
                          );
                          _titleController.clear();
                          _bodyController.clear();
                        }
                      },
                      child: Text('COMMIT', style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Divider(color: ruleBorder, height: 16, thickness: 0.8),

          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: ruleBorder, width: 0.8)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.title.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(item.title.toUpperCase(),
                                    style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.02)),
                              ),
                            Text(item.content, style: TextStyle(color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF404040), fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _showDeleteConfirmation(context, item.id),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(Icons.delete_outline_rounded, color: textSub, size: 20),
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}