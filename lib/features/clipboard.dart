import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:file_picker/file_picker.dart';
import '../core/database.dart';
import '../main.dart';

class ClipboardScreen extends ConsumerWidget {
  const ClipboardScreen({super.key});

  Future<void> _accessGallery(WidgetRef ref) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null) {
      for (var file in result.files) {
        if (file.path != null) {
          ref.read(localDatabaseProvider.notifier).insertItem(file.path!, 'image_clip');
        }
      }
    }
  }

  void _showImagePreview(BuildContext context, String filePath, bool isDark, Color borderColor) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Preview',
      barrierColor: Colors.black.withOpacity(isDark ? 0.85 : 0.6),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.all(32),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Image.file(
                        File(filePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F5),
                      border: Border(top: BorderSide(color: borderColor, width: 0.8)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            filePath.split(Platform.pathSeparator).last.toUpperCase(),
                            style: TextStyle(
                              color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.05,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            'CLOSE',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.05,
                            ),
                          ),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);
    final items = ref.watch(localDatabaseProvider)
        .where((e) => e.type == 'clip' || e.type == 'image_clip')
        .toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final containerBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEEEEEE);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CLIPBOARD REGISTRY',
            style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
          ),
          const SizedBox(height: 16),

          InkWell(
            onTap: () => _accessGallery(ref),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              // FIXED: The border parameter is now correctly inside BoxDecoration
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 0.8),
                color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF9F9F9),
              ),
              alignment: Alignment.center,
              child: Text(
                'ACCESS GALLERY SYSTEM',
                style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.05),
              ),
            ),
          ),

          Divider(color: borderColor, height: 32, thickness: 0.8),

          Expanded(
            child: items.isEmpty
                ? Center(
              child: Text(
                'NO CAPTURES INSTANTIATED',
                style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05),
              ),
            )
                : MasonryGridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];

                if (item.type == 'image_clip') {
                  return GestureDetector(
                    onTap: () => _showImagePreview(context, item.content, isDark, borderColor),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: borderColor, width: 0.8),
                        color: containerBg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.file(
                            File(item.content),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                padding: const EdgeInsets.all(12),
                                child: Text('MEDIA REF BROKEN', style: TextStyle(color: Colors.red[400], fontSize: 11)),
                              );
                            },
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8.0),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: borderColor, width: 0.8)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.content.split(Platform.pathSeparator).last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: textSub, fontSize: 10),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => ref.read(localDatabaseProvider.notifier).deleteItem(item.id),
                                  child: Icon(Icons.close, color: textSub, size: 12),
                                )
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.all(12),
                  color: containerBg,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.content,
                          style: TextStyle(color: textSub, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => ref.read(localDatabaseProvider.notifier).deleteItem(item.id),
                        child: Icon(Icons.close, color: textSub, size: 12),
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