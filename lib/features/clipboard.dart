import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
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

// --- MAIN INTERSPACE WORKSPACE ---
class ClipboardScreen extends ConsumerStatefulWidget {
  const ClipboardScreen({super.key});

  @override
  ConsumerState<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends ConsumerState<ClipboardScreen> {
  final PageController _pageController = PageController(initialPage: 0);
  int _activePageIndex = 0;

  // SYSTEM MEDIA ARRAY HOLDERS
  final List<AssetEntity> _galleryAssets = [];
  bool _isLoadingGallery = false;
  AssetPathEntity? _currentAlbum;

  // HIGH PERFORMANCE PERSISTENT MEMORY CACHE CONTAINERS
  final Map<String, Uint8List> _thumbnailCache = {};
  final Set<String> _loadingIds = {};

  // --- MULTI-SELECT STATE ARRAYS ---
  bool _isSelectMode = false;
  final Set<String> _selectedGalleryIds = {};
  final Set<String> _selectedImportedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchEntireGalleryAllAtOnce();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    setState(() {
      _activePageIndex = index;
      // Reset select mode tracking on tab swap to eliminate registry pollution
      _isSelectMode = false;
      _selectedGalleryIds.clear();
      _selectedImportedIds.clear();
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // CORE ENGINE: FETCH ALL FILE POINTERS AT ONCE
  Future<void> _fetchEntireGalleryAllAtOnce() async {
    if (_isLoadingGallery) return;
    setState(() => _isLoadingGallery = true);

    try {
      if (_currentAlbum == null) {
        final PermissionState permission = await PhotoManager.requestPermissionExtend();
        if (permission.isAuth || permission.hasAccess) {
          final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
            type: RequestType.image,
            filterOption: FilterOptionGroup(
              orders: [
                const OrderOption(type: OrderOptionType.createDate, asc: false),
              ],
            ),
          );
          if (albums.isNotEmpty) {
            _currentAlbum = albums.first;
          }
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PERMISSION DENIED')));
          setState(() => _isLoadingGallery = false);
          return;
        }
      }

      if (_currentAlbum != null) {
        final int totalAssetsCount = await _currentAlbum!.assetCountAsync;

        final List<AssetEntity> allAssets = await _currentAlbum!.getAssetListRange(
          start: 0,
          end: totalAssetsCount,
        );

        setState(() {
          _galleryAssets.clear();
          _galleryAssets.addAll(allAssets);
        });

        _preloadTopThumbnails(allAssets);
      }
    } catch (e) {
      debugPrint('Media registry processing exception: $e');
    } finally {
      setState(() => _isLoadingGallery = false);
    }
  }

  void _preloadTopThumbnails(List<AssetEntity> assets) {
    final int targetPreloadCount = assets.length > 150 ? 150 : assets.length;
    for (int i = 0; i < targetPreloadCount; i++) {
      _loadSingleThumbnail(assets[i]);
    }
  }

  void _loadSingleThumbnail(AssetEntity asset) {
    if (_thumbnailCache.containsKey(asset.id) || _loadingIds.contains(asset.id)) return;
    _loadingIds.add(asset.id);

    asset.thumbnailDataWithSize(const ThumbnailSize(360, 360)).then((data) {
      if (data != null && mounted) {
        setState(() {
          _thumbnailCache[asset.id] = data;
        });
      }
      _loadingIds.remove(asset.id);
    }).catchError((_) {
      _loadingIds.remove(asset.id);
    });
  }

  Future<void> _refreshGallery() async {
    setState(() {
      _galleryAssets.clear();
      _thumbnailCache.clear();
      _loadingIds.clear();
      _currentAlbum = null;
    });
    await _fetchEntireGalleryAllAtOnce();
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

  // --- REGISTRY BULK PROCESSING MATRIX ENGINES ---
  Future<void> _handleBulkDelete() async {
    if (_activePageIndex == 0) {
      if (_selectedGalleryIds.isEmpty) return;
      try {
        final List<String> result = await PhotoManager.editor.deleteWithIds(_selectedGalleryIds.toList());
        if (result.isNotEmpty) {
          setState(() {
            _selectedGalleryIds.clear();
            _isSelectMode = false;
          });
          _refreshGallery();
        }
      } catch (e) {
        debugPrint('Bulk gallery clear processing crash: $e');
      }
    } else {
      if (_selectedImportedIds.isEmpty) return;
      try {
        final allItems = ref.read(localDatabaseProvider);
        for (final id in _selectedImportedIds) {
          final target = allItems.firstWhere((e) => e.id == id);
          final file = File(target.content);
          if (await file.exists()) {
            await file.delete();
          }
          await ref.read(localDatabaseProvider.notifier).deleteItem(id);
        }
        setState(() {
          _selectedImportedIds.clear();
          _isSelectMode = false;
        });
      } catch (e) {
        debugPrint('Bulk isolated target clear processing crash: $e');
      }
    }
  }

  Future<void> _handleBulkLike() async {
    if (_activePageIndex == 0) {
      if (_selectedGalleryIds.isEmpty) return;
      List<String> pathsToInsert = [];
      for (final id in _selectedGalleryIds) {
        final asset = _galleryAssets.firstWhere((e) => e.id == id, orElse: () => _galleryAssets.first);
        final file = await asset.file;
        if (file != null) pathsToInsert.add(file.path);
      }
      if (pathsToInsert.isNotEmpty) {
        await ref.read(localDatabaseProvider.notifier).insertMultipleItems(pathsToInsert, 'imported_clip');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ADDED ${pathsToInsert.length} REFS TO IMPORTED TAB')));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MEDIA ALREADY PERSISTED INSIDE WORKSPACE')));
      }
    }
    setState(() {
      _selectedGalleryIds.clear();
      _selectedImportedIds.clear();
      _isSelectMode = false;
    });
  }

  Future<void> _handleBulkDislike() async {
    final allItems = ref.read(localDatabaseProvider);
    int counter = 0;

    if (_activePageIndex == 0) {
      if (_selectedGalleryIds.isEmpty) return;
      for (final id in _selectedGalleryIds) {
        final asset = _galleryAssets.firstWhere((e) => e.id == id, orElse: () => _galleryAssets.first);
        final file = await asset.file;
        if (file != null) {
          final matches = allItems.where((e) => e.type == 'imported_clip' && e.content == file.path).toList();
          for (final item in matches) {
            await ref.read(localDatabaseProvider.notifier).deleteItem(item.id);
            counter++;
          }
        }
      }
    } else {
      if (_selectedImportedIds.isEmpty) return;
      for (final id in _selectedImportedIds) {
        await ref.read(localDatabaseProvider.notifier).deleteItem(id);
        counter++;
      }
    }

    if (mounted && counter > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('REMOVED $counter REFS FROM WORKSPACE MATCHES')));
    }
    setState(() {
      _selectedGalleryIds.clear();
      _selectedImportedIds.clear();
      _isSelectMode = false;
    });
  }

  // SYSTEM ASSET FULLSCREEN PREVIEWER WITH ACTION MATRIX
  void _showGalleryImagePreview(AssetEntity asset, bool isDark, Color borderColor) async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final File? file = await asset.file;
    if (file == null) return;
    final String filePath = file.path;
    final String folderPath = file.parent.path;

    if (!mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, anim1, anim2) {
        bool showBottomBar = true;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) {
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                }
              },
              child: Scaffold(
                backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
                body: Stack(
                  children: [
                    // FULL SCREEN CANVAS WITH ACTION TOGGLE GESTURE MAPPER
                    GestureDetector(
                      onTap: () {
                        setStateDialog(() {
                          showBottomBar = !showBottomBar;
                        });
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: InteractiveViewer(
                          maxScale: 5.0,
                          child: Image.file(file, fit: BoxFit.contain),
                        ),
                      ),
                    ),

                    // TOP LEFT CORNER [RETURN] BUTTON (UNAFFECTED BY DYNAMIC CANVAS TOGGLE)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: 16,
                      child: GestureDetector(
                        onTap: () {
                          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black : Colors.white,
                            border: Border.all(color: borderColor, width: 0.8),
                          ),
                          child: Text(
                            '[RETURN]',
                            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                          ),
                        ),
                      ),
                    ),

                    // BOTTOM INFO AND THREE BUTTON NAVIGATION BAR (DYNAMIC SLIDE LAYOUT)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        offset: showBottomBar ? Offset.zero : const Offset(0, 1),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.fastOutSlowIn,
                        child: Consumer(
                          builder: (context, ref, child) {
                            final allItems = ref.watch(localDatabaseProvider);
                            final bool isLiked = allItems.any((e) => e.type == 'imported_clip' && e.content == filePath);

                            return Container(
                              width: double.infinity,
                              padding: EdgeInsets.only(
                                top: 16,
                                left: 16,
                                right: 16,
                                bottom: MediaQuery.of(context).padding.bottom + 16,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F5),
                                border: Border(top: BorderSide(color: borderColor, width: 0.8)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PATH: $folderPath'.toUpperCase(),
                                    style: TextStyle(color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252), fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 0.03),
                                    maxLines: 2, overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.share, color: isDark ? Colors.white : Colors.black, size: 20),
                                        onPressed: () async {
                                          if (filePath.isNotEmpty) {
                                            await Share.shareXFiles([XFile(filePath)]);
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(
                                            isLiked ? Icons.favorite : Icons.favorite_border,
                                            color: isDark ? Colors.white : Colors.black,
                                            size: 20
                                        ),
                                        onPressed: () async {
                                          final allCurrentItems = ref.read(localDatabaseProvider);
                                          CaptureItem? existingItem;
                                          for (final item in allCurrentItems) {
                                            if (item.type == 'imported_clip' && item.content == filePath) {
                                              existingItem = item;
                                              break;
                                            }
                                          }

                                          // All pop-up alerts completely removed. Database runs purely in the background.
                                          if (existingItem != null) {
                                            await ref.read(localDatabaseProvider.notifier).deleteItem(existingItem.id);
                                          } else {
                                            await ref.read(localDatabaseProvider.notifier).insertMultipleItems([filePath], 'imported_clip');
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 20),
                                        onPressed: () => _confirmDeleteGalleryAsset(asset),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // GALLERY DELETION CONFIRMATION DIALOG BOX
  void _confirmDeleteGalleryAsset(AssetEntity asset) {
    final isDark = ref.read(themeProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
        shape: RoundedRectangleBorder(side: BorderSide(color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5), width: 0.8)),
        title: Text('DELETE IMAGE', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
        content: Text('ARE YOU SURE YOU WANT TO DELETE THIS IMAGE FROM YOUR DEVICE CORES?', style: TextStyle(color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252), fontSize: 11)),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('CANCEL', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 11)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final List<String> result = await PhotoManager.editor.deleteWithIds([asset.id]);
                    if (result.isNotEmpty) {
                      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                      if (mounted) Navigator.pop(context);
                      _refreshGallery();
                    }
                  } catch (e) {
                    debugPrint('Native deletion exception: $e');
                  }
                },
                child: const Text('DELETE', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // LOCAL MEMORY FILE HARDWARE PREVIEWER WITH ACTION MATRIX
  void _showImagePreview(CaptureItem item, bool isDark, Color borderColor) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final filePath = item.content;
    final folderPath = File(filePath).parent.path;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, anim1, anim2) {
        bool showBottomBar = true;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) {
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                }
              },
              child: Scaffold(
                backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
                body: Stack(
                  children: [
                    // FULL SCREEN CANVAS WITH ACTION TOGGLE GESTURE MAPPER
                    GestureDetector(
                      onTap: () {
                        setStateDialog(() {
                          showBottomBar = !showBottomBar;
                        });
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: InteractiveViewer(
                          maxScale: 5.0,
                          child: Image.file(File(filePath), fit: BoxFit.contain),
                        ),
                      ),
                    ),

                    // TOP LEFT CORNER [RETURN] BUTTON (UNAFFECTED BY DYNAMIC CANVAS TOGGLE)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: 16,
                      child: GestureDetector(
                        onTap: () {
                          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black : Colors.white,
                            border: Border.all(color: borderColor, width: 0.8),
                          ),
                          child: Text(
                            '[RETURN]',
                            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                          ),
                        ),
                      ),
                    ),

                    // BOTTOM INFO AND THREE BUTTON NAVIGATION BAR (DYNAMIC SLIDE LAYOUT)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        offset: showBottomBar ? Offset.zero : const Offset(0, 1),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.fastOutSlowIn,
                        child: Consumer(
                          builder: (context, ref, child) {
                            final allItems = ref.watch(localDatabaseProvider);
                            final bool isLiked = allItems.any((e) => e.type == 'imported_clip' && e.content == filePath);

                            return Container(
                              width: double.infinity,
                              padding: EdgeInsets.only(
                                top: 16,
                                left: 16,
                                right: 16,
                                bottom: MediaQuery.of(context).padding.bottom + 16,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F5),
                                border: Border(top: BorderSide(color: borderColor, width: 0.8)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PATH: $folderPath'.toUpperCase(),
                                    style: TextStyle(color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252), fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 0.03),
                                    maxLines: 2, overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.share, color: isDark ? Colors.white : Colors.black, size: 20),
                                        onPressed: () async {
                                          await Share.shareXFiles([XFile(filePath)]);
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(
                                            isLiked ? Icons.favorite : Icons.favorite_border,
                                            color: isDark ? Colors.white : Colors.black,
                                            size: 20
                                        ),
                                        onPressed: () async {
                                          final allCurrentItems = ref.read(localDatabaseProvider);
                                          CaptureItem? existingItem;
                                          for (final dItem in allCurrentItems) {
                                            if (dItem.type == 'imported_clip' && dItem.content == filePath) {
                                              existingItem = dItem;
                                              break;
                                            }
                                          }

                                          // All pop-up alerts completely removed. Database runs purely in the background.
                                          if (existingItem != null) {
                                            await ref.read(localDatabaseProvider.notifier).deleteItem(existingItem.id);
                                          } else {
                                            await ref.read(localDatabaseProvider.notifier).insertMultipleItems([filePath], 'imported_clip');
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 20),
                                        onPressed: () => _confirmDeleteImportedItem(item),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // IMPORTED MEDIA CONTEXT DELETION CONFIRMATION DIALOG BOX
  void _confirmDeleteImportedItem(CaptureItem item) {
    final isDark = ref.read(themeProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
        shape: RoundedRectangleBorder(side: BorderSide(color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5), width: 0.8)),
        title: Text('DELETE IMAGE', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
        content: Text('ARE YOU SURE YOU WANT TO WIPE THIS REFS MATRIX OUT OF THE APPLICATION PERSISTENT STORAGE AND DISK DEVICE MEMORY?', style: TextStyle(color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252), fontSize: 11)),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('CANCEL', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 11)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final file = File(item.content);
                    if (await file.exists()) {
                      await file.delete();
                    }
                    await ref.read(localDatabaseProvider.notifier).deleteItem(item.id);
                    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    debugPrint('Local file deletion error: $e');
                  }
                },
                child: const Text('DELETE', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ULTRA PERFORMANCE PINTEREST-STYLE STAGGERED GRID ENGINE
  Widget _buildGalleryGrid({
    required List<AssetEntity> assets,
    required int columns,
    required bool isDark,
    required Color borderColor,
    required Color containerBg,
    required Color textSub,
  }) {
    if (assets.isEmpty && _isLoadingGallery) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white : Colors.black),
        ),
      );
    }

    if (assets.isEmpty && !_isLoadingGallery) {
      return Center(
        child: Text(
          'NO MEDIA FOUND IN SYSTEM HARDWARE',
          style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05),
        ),
      );
    }

    return MasonryGridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      physics: const ClampingScrollPhysics(),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        final cachedBytes = _thumbnailCache[asset.id];
        final bool isSelected = _selectedGalleryIds.contains(asset.id);

        final double nativeWidth = asset.width.toDouble();
        final double nativeHeight = asset.height.toDouble();
        final double calculatedRatio = (nativeWidth > 0 && nativeHeight > 0) ? (nativeWidth / nativeHeight) : 1.0;

        if (cachedBytes == null) {
          _loadSingleThumbnail(asset);
        }

        return GestureDetector(
          onTap: _isSelectMode
              ? () {
            setState(() {
              if (isSelected) {
                _selectedGalleryIds.remove(asset.id);
              } else {
                _selectedGalleryIds.add(asset.id);
              }
            });
          }
              : () => _showGalleryImagePreview(asset, isDark, borderColor),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 0.8),
                  color: containerBg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: calculatedRatio,
                      child: cachedBytes != null
                          ? Image.memory(
                        cachedBytes,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        gaplessPlayback: true,
                      )
                          : Container(
                        color: containerBg,
                      ),
                    ),
                    if (columns <= 2)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: borderColor, width: 0.8))),
                        child: Text(
                          asset.title ?? 'IMG',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textSub, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
              // --- CONFIGURABLE BOUNDARY SELECT INDICATOR ---
              if (_isSelectMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark ? Colors.white : Colors.black,
                        width: 1.5,
                      ),
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.transparent,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // RENDERS SELECTED IMPORTED SYSTEM REFS WITH ORIGINAL PINTEREST FLOW
  Widget _buildImportedGrid({
    required List<CaptureItem> items,
    required int columns,
    required bool isDark,
    required Color borderColor,
    required Color containerBg,
    required Color textMain,
    required Color textSub,
    VoidCallback? onEmptyActionTap,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'IMPORT SPECIFIC ASSETS HERE TO ISOLATE THEM FOR INSTANT WORKSPACE ACCESS, ELIMINATING THE NEED TO SEARCH THROUGH THE ENTIRE GALLERY DEVICE STORAGE.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSub, fontSize: 11.5, height: 1.6, letterSpacing: 0.03),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onEmptyActionTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: containerBg, border: Border.all(color: textMain, width: 0.8)),
                  alignment: Alignment.center,
                  child: Icon(Icons.add, color: textMain, size: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return MasonryGridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      physics: const ClampingScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final bool isSelected = _selectedImportedIds.contains(item.id);

        return GestureDetector(
          onTap: _isSelectMode
              ? () {
            setState(() {
              if (isSelected) {
                _selectedImportedIds.remove(item.id);
              } else {
                _selectedImportedIds.add(item.id);
              }
            });
          }
              : () => _showImagePreview(item, isDark, borderColor),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8), color: containerBg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.file(
                      File(item.content),
                      fit: BoxFit.cover,
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
              // --- CONFIGURABLE BOUNDARY SELECT INDICATOR ---
              if (_isSelectMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark ? Colors.white : Colors.black,
                        width: 1.5,
                      ),
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.transparent,
                    ),
                  ),
                ),
            ],
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

    final importedItems = allItems.where((e) => e.type == 'imported_clip').toList().reversed.toList();

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
                  // --- BUTTON MATRIX 1: REFRESH / IMPORT TO DYNAMIC BULK DELETE ---
                  GestureDetector(
                    onTap: () {
                      if (_isSelectMode) {
                        _handleBulkDelete();
                      } else {
                        _activePageIndex == 0 ? _refreshGallery() : _importSelectedMedia();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          border: Border.all(color: _isSelectMode ? Colors.red.shade400 : borderColor, width: 0.8),
                          color: _isSelectMode ? Colors.red.withOpacity(0.1) : (isDark ? Colors.white : Colors.black)
                      ),
                      child: Text(
                        _isSelectMode ? 'DELETE' : (_activePageIndex == 0 ? 'REFRESH' : 'IMPORT'),
                        style: TextStyle(
                            color: _isSelectMode ? Colors.red.shade400 : (isDark ? Colors.black : Colors.white),
                            fontSize: 11,
                            fontWeight: FontWeight.bold
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // --- BUTTON MATRIX 2: DYNAMIC SELECT TO UNDO CONTROLLER ---
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isSelectMode = !_isSelectMode;
                        if (!_isSelectMode) {
                          _selectedGalleryIds.clear();
                          _selectedImportedIds.clear();
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8), color: containerBg),
                      child: Text(
                        _isSelectMode ? 'UNDO' : 'SELECT',
                        style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // --- BUTTON MATRIX 3: SCALING [+] TO BULK HEART ACTIONS ---
                  GestureDetector(
                    onTap: () {
                      if (_isSelectMode) {
                        _handleBulkLike();
                      } else {
                        ref.read(gridColumnsProvider.notifier).makeItemsLarger();
                      }
                    },
                    child: Container(
                      padding: _isSelectMode ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8), color: containerBg),
                      child: _isSelectMode
                          ? Icon(Icons.favorite, color: textMain, size: 14) // Adheres seamlessly to Light/Dark modes
                          : Text('+', style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // --- BUTTON MATRIX 4: SCALING [-] TO BULK DISLIKE ACTIONS ---
                  GestureDetector(
                    onTap: () {
                      if (_isSelectMode) {
                        _handleBulkDislike();
                      } else {
                        ref.read(gridColumnsProvider.notifier).makeItemsSmaller();
                      }
                    },
                    child: Container(
                      padding: _isSelectMode ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8), color: containerBg),
                      child: _isSelectMode
                          ? Icon(Icons.favorite_border, color: textSub, size: 14)
                          : Text('-', style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.bold)),
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
                _buildGalleryGrid(
                  assets: _galleryAssets,
                  columns: columns,
                  isDark: isDark,
                  borderColor: borderColor,
                  containerBg: containerBg,
                  textSub: textSub,
                ),
                _buildImportedGrid(
                  items: importedItems,
                  columns: columns,
                  isDark: isDark,
                  borderColor: borderColor,
                  containerBg: containerBg,
                  textMain: textMain,
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