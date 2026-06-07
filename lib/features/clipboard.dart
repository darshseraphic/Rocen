import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/database.dart';
import '../main.dart';

// --- PERSISTED DENSITY STATE NOTIFIER ---
class GridColumnsNotifier extends Notifier<int> {
  static const String _boxName = 'rocen_settings_box';

  @override
  int build() {
    return Hive.box(_boxName).get('grid_columns', defaultValue: 2);
  }

  void makeItemsSmaller() {
    if (state < 6) {
      state++;
      Hive.box(_boxName).put('grid_columns', state);
    }
  }

  void makeItemsLarger() {
    if (state > 1) {
      state--;
      Hive.box(_boxName).put('grid_columns', state);
    }
  }
}

final gridColumnsProvider = NotifierProvider<GridColumnsNotifier, int>(GridColumnsNotifier.new);

// --- MAIN INTERFACE WORKSPACE ---
class ClipboardScreen extends ConsumerStatefulWidget {
  const ClipboardScreen({super.key});

  @override
  ConsumerState<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends ConsumerState<ClipboardScreen> {
  final PageController _pageController = PageController(initialPage: 0);
  int _activePageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    setState(() => _activePageIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _autoFetchWholeGallery() async {
    final PermissionState permission = await PhotoManager.requestPermissionExtend();

    if (permission.isAuth || permission.hasAccess) {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      final List<String> loadedFilePaths = [];

      for (var album in albums) {
        final int count = await album.assetCountAsync;
        final List<AssetEntity> assets = await album.getAssetListRange(start: 0, end: count);

        for (var asset in assets) {
          final File? file = await asset.file;
          if (file != null) loadedFilePaths.add(file.path);
        }
      }

      if (loadedFilePaths.isNotEmpty) {
        await ref.read(localDatabaseProvider.notifier).insertMultipleItems(loadedFilePaths, 'gallery_clip');
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PERMISSION DENIED')));
    }
  }

  Future<void> _importSelectedMedia() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);

      if (result != null) {
        final List<String> chosenPaths = result.paths.whereType<String>().toList();
        if (chosenPaths.isNotEmpty) {
          await ref.read(localDatabaseProvider.notifier).insertMultipleItems(chosenPaths, 'imported_clip');
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ERROR: ${e.toString().toUpperCase()}')));
    }
  }

  void _showImagePreview(String filePath, bool isDark, Color borderColor) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
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
                      child: Image.file(File(filePath), fit: BoxFit.contain),
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
                            style: TextStyle(color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252), fontSize: 10, fontWeight: FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Text('CLOSE', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 10, fontWeight: FontWeight.w600)),
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

  Widget _buildGrid({
    required List<CaptureItem> items,
    required int columns,
    required bool isDark,
    required Color borderColor,
    required Color containerBg,
    required Color textSub,
    VoidCallback? onEmptyActionTap,
  }) {
    if (items.isEmpty) {
      if (onEmptyActionTap != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'IMPORT SPECIFIC ASSETS HERE TO ISOLATE THEM FOR INSTANT WORKSPACE ACCESS, ELIMINATING THE NEED TO SEARCH THROUGH THE ENTIRE GALLERY DEVICE STORAGE.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSub,
                    fontSize: 11.5,
                    height: 1.6,
                    letterSpacing: 0.03,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: onEmptyActionTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: containerBg,
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Center(
        child: Text(
          'NO MEDIA FOUND IN THIS CATEGORY',
          style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05),
        ),
      );
    }

    return MasonryGridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () => _showImagePreview(item.content, isDark, borderColor),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8), color: containerBg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.file(
                  File(item.content),
                  fit: BoxFit.cover,
                  cacheWidth: 280,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(padding: const EdgeInsets.all(12), child: Text('BROKEN REF', style: TextStyle(color: Colors.red[400], fontSize: 9)));
                  },
                ),
                if (columns <= 2)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: borderColor, width: 0.8))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.content.split(Platform.pathSeparator).last,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final columns = ref.watch(gridColumnsProvider);
    final allItems = ref.watch(localDatabaseProvider);

    final galleryItems = allItems.where((e) => e.type == 'gallery_clip').toList();
    final importedItems = allItems.where((e) => e.type == 'imported_clip').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final containerBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEEEEEE);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MEDIA REGISTRY',
                style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
              ),

              Row(
                children: [
                  GestureDetector(
                    onTap: () => _activePageIndex == 0 ? _autoFetchWholeGallery() : _importSelectedMedia(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8), color: isDark ? Colors.white : Colors.black),
                      child: Text('FETCH', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => ref.read(gridColumnsProvider.notifier).makeItemsLarger(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8), color: containerBg),
                      child: Text('+', style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => ref.read(gridColumnsProvider.notifier).makeItemsSmaller(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8), color: containerBg),
                      child: Text('-', style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _switchTab(0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: _activePageIndex == 0 ? textMain : borderColor, width: _activePageIndex == 0 ? 1.5 : 0.8),
                      color: _activePageIndex == 0 ? containerBg : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'ACCESS GALLERY',
                      style: TextStyle(color: _activePageIndex == 0 ? textMain : textSub, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.05),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _switchTab(1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: _activePageIndex == 1 ? textMain : borderColor, width: _activePageIndex == 1 ? 1.5 : 0.8),
                      color: _activePageIndex == 1 ? containerBg : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'IMPORT MEDIA',
                      style: TextStyle(color: _activePageIndex == 1 ? textMain : textSub, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.05),
                    ),
                  ),
                ),
              ),
            ],
          ),

          Divider(color: borderColor, height: 32, thickness: 0.8),

          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _activePageIndex = index),
              children: [
                _buildGrid(
                  items: galleryItems,
                  columns: columns,
                  isDark: isDark,
                  borderColor: borderColor,
                  containerBg: containerBg,
                  textSub: textSub,
                ),
                _buildGrid(
                  items: importedItems,
                  columns: columns,
                  isDark: isDark,
                  borderColor: borderColor,
                  containerBg: containerBg,
                  textSub: textSub,
                  onEmptyActionTap: _importSelectedMedia,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}