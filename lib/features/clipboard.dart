import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../core/database.dart';
import '../main.dart';

/// A source-agnostic view over a single gallery [AssetEntity] or imported
/// [CaptureItem], so the full-screen viewer can work with either without
/// duplicating its logic.
enum _ClipMediaKind { image, video }

class _ClipMediaRef {
  final String id;
  final Future<File?> Function() resolveFile;
  final _ClipMediaKind kind;
  final Uint8List? placeholderBytes;

  _ClipMediaRef({
    required this.id,
    required this.resolveFile,
    required this.kind,
    this.placeholderBytes,
  });

  factory _ClipMediaRef.fromAsset(AssetEntity asset, {Uint8List? thumbnail}) {
    return _ClipMediaRef(
      id: asset.id,
      resolveFile: () => asset.file,
      kind: asset.type == AssetType.video
          ? _ClipMediaKind.video
          : _ClipMediaKind.image,
      placeholderBytes: thumbnail,
    );
  }

  factory _ClipMediaRef.fromCaptureItem(CaptureItem item) {
    return _ClipMediaRef(
      id: item.id,
      resolveFile: () async => File(item.content),
      kind: _isVideoPath(item.content)
          ? _ClipMediaKind.video
          : _ClipMediaKind.image,
    );
  }

  static bool _isVideoPath(String path) {
    final String lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }
}

/// Result returned by the full-screen viewer so the caller can refresh its
/// underlying grid (e.g. a newly saved crop was added, or the item behind
/// [currentIndex] was deleted/liked while browsing).
class _ClipViewerResult {
  final int lastIndex;
  final bool galleryChanged;
  const _ClipViewerResult(
      {required this.lastIndex, this.galleryChanged = false});
}

/// Actions the normal 64px toolbar can request of the surrounding screen.
/// Kept as callbacks so the viewer stays agnostic of whether it is showing
/// a device-gallery [AssetEntity] or an imported [CaptureItem].
class _ClipViewerActions {
  final Future<bool> Function(_ClipMediaRef media) isLiked;
  final Future<void> Function(_ClipMediaRef media) toggleLike;
  final Future<void> Function(_ClipMediaRef media) delete;
  final String deleteConfirmTitle;
  final String deleteConfirmMessage;

  const _ClipViewerActions({
    required this.isLiked,
    required this.toggleLike,
    required this.delete,
    required this.deleteConfirmTitle,
    required this.deleteConfirmMessage,
  });
}

/// Shared full-screen media viewer for both the device gallery and the
/// imported/liked tab. Handles image + video display, pinch/double-tap zoom
/// (locked while the normal toolbar is visible), 90-degree rotation of the
/// media layer only, the normal/edit toolbar slide transition, image crop,
/// and copy-to-clipboard.
class _ClipMediaViewer extends ConsumerStatefulWidget {
  final List<_ClipMediaRef> items;
  final int initialIndex;
  final bool isDark;
  final Color borderColor;
  final _ClipViewerActions actions;

  const _ClipMediaViewer({
    required this.items,
    required this.initialIndex,
    required this.isDark,
    required this.borderColor,
    required this.actions,
  });

  @override
  ConsumerState<_ClipMediaViewer> createState() => _ClipMediaViewerState();
}

class _ClipMediaViewerState extends ConsumerState<_ClipMediaViewer>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentIndex;

  bool _showNormalToolbar = true;
  bool _isEditMode = false;
  bool _isCropMode = false;

  static const double _toolbarHeight = 64.0;
  static const Duration _editTransitionDuration = Duration(milliseconds: 500);

  // Per-item transform state, keyed by list index so it never leaks between
  // media items when paging.
  final Map<int, TransformationController> _transformControllers = {};
  final Map<int, int> _quarterTurns = {};
  final Map<int, int> _doubleTapStage = {};

  final Map<int, VideoPlayerController> _videoControllers = {};

  bool _showCopiedNotice = false;
  bool _didModifyGallery = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _transformFor(int index) {
    return _transformControllers.putIfAbsent(
        index, () => TransformationController());
  }

  int _rotationFor(int index) => _quarterTurns[index] ?? 0;

  void _resetItemState(int index) {
    _transformControllers[index]?.value = Matrix4.identity();
    _quarterTurns[index] = 0;
    _doubleTapStage[index] = 0;
    _zoomAscending[index] = true;
  }

  final Map<int, Future<VideoPlayerController>> _videoControllerFutures = {};

  Future<VideoPlayerController> _videoControllerFor(int index, File file) {
    final cached = _videoControllerFutures[index];
    if (cached != null) return cached;

    final future = _initVideoController(index, file);
    _videoControllerFutures[index] = future;
    return future;
  }

  Future<VideoPlayerController> _initVideoController(
      int index, File file) async {
    final controller = VideoPlayerController.file(file);
    _videoControllers[index] = controller;
    await controller.initialize();
    // Keeps the outer viewer (where the fixed ROTATE control lives) in sync
    // with play/pause state, since ROTATE must hide while this item is
    // actively playing.
    controller.addListener(_onAnyVideoValueChanged);
    return controller;
  }

  void _onAnyVideoValueChanged() {
    if (mounted) setState(() {});
  }

  void _onPageChanged(int newIndex) {
    for (final entry in _videoControllers.entries) {
      if (entry.key != newIndex) {
        entry.value.pause();
      }
    }
    // Per spec: moving to another media item always resets that item's
    // zoom/rotation/edit/crop state, even if it was visited before.
    _resetItemState(newIndex);
    setState(() {
      _currentIndex = newIndex;
      _isEditMode = false;
      _isCropMode = false;
      _showNormalToolbar = true;
    });
  }

  void _toggleToolbarVisibility() {
    if (_isEditMode) return;
    setState(() {
      _showNormalToolbar = !_showNormalToolbar;
    });
  }

  Offset? _pendingDoubleTapPosition;
  // Tracks whether the zoom is currently climbing towards 3x (true) or
  // descending back towards 1x (false), per item index.
  final Map<int, bool> _zoomAscending = {};

  void _handleDoubleTapDown(TapDownDetails details) {
    _pendingDoubleTapPosition = details.localPosition;
  }

  /// Bounces the zoom level: 1x -> 2x -> 3x -> 2x -> 1x -> 2x -> ...,
  /// each step anchored at wherever the double-tap landed.
  void _handleDoubleTap(int index) {
    if (_showNormalToolbar) return; // zoom locked while normal bar is visible
    final controller = _transformFor(index);
    final int currentStage = _doubleTapStage[index] ?? 0; // 0=1x, 1=2x, 2=3x
    bool ascending = _zoomAscending[index] ?? true;

    int nextStage;
    if (ascending) {
      nextStage = currentStage + 1;
      if (nextStage >= 2) ascending = false; // reached 3x, bounce back next
    } else {
      nextStage = currentStage - 1;
      if (nextStage <= 0) ascending = true; // reached 1x, climb again next
    }
    nextStage = nextStage.clamp(0, 2);

    _doubleTapStage[index] = nextStage;
    _zoomAscending[index] = ascending;

    final double targetScale = nextStage + 1.0; // 0->1x, 1->2x, 2->3x
    final Offset focalPoint = _pendingDoubleTapPosition ?? Offset.zero;
    final Matrix4 target = targetScale == 1.0
        ? Matrix4.identity()
        : _matrixZoomedAt(focalPoint, targetScale, controller.value);
    _animateMatrix(controller, target);
  }

  /// Builds a transform that scales to [targetScale] while keeping
  /// [focalPoint] (in the widget's local coordinates) visually fixed in
  /// place, the same way native pinch-zoom anchors under your fingers.
  Matrix4 _matrixZoomedAt(
      Offset focalPoint, double targetScale, Matrix4 current) {
    final Matrix4 target = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, targetScale, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    return target;
  }

  void _animateMatrix(TransformationController controller, Matrix4 target) {
    final Matrix4 begin = controller.value;
    final animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    final animation = Matrix4Tween(begin: begin, end: target).animate(
      CurvedAnimation(parent: animationController, curve: Curves.easeOutCubic),
    );
    void tick() => controller.value = animation.value;
    animation.addListener(tick);
    animationController.forward().whenComplete(() {
      animation.removeListener(tick);
      animationController.dispose();
    });
  }

  /// ROTATE is shown for images always, and for videos only while that
  /// video is paused/stopped - it must not be visible during playback.
  bool _shouldShowRotateControl() {
    final media = widget.items[_currentIndex];
    if (media.kind == _ClipMediaKind.image) return true;
    final controller = _videoControllers[_currentIndex];
    if (controller == null) return true; // not yet initialized/loaded
    return !controller.value.isPlaying;
  }

  void _rotate(int index) {
    setState(() {
      _quarterTurns[index] = (_rotationFor(index) + 1) % 4;
    });
  }

  void _enterEditMode() {
    setState(() {
      _showNormalToolbar = false;
    });
    Future.delayed(_editTransitionDuration, () {
      if (!mounted) return;
      setState(() {
        _isEditMode = true;
      });
    });
  }

  void _exitEditMode() {
    setState(() {
      _isEditMode = false;
      _isCropMode = false;
    });
    Future.delayed(_editTransitionDuration, () {
      if (!mounted) return;
      setState(() {
        _showNormalToolbar = true;
      });
    });
  }

  String _briefNoticeMessage = 'COPIED';

  void _showBriefNotice(String message) {
    setState(() {
      _briefNoticeMessage = message;
      _showCopiedNotice = true;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _showCopiedNotice = false);
    });
  }

  Future<void> _handleCopy(_ClipMediaRef media) async {
    final file = await media.resolveFile();
    if (!mounted) return;
    if (file == null || !await file.exists()) {
      if (mounted) _showFailureNotice('COULD NOT LOCATE FILE TO COPY.');
      return;
    }
    if (!mounted) return;

    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      _showFailureNotice('CLIPBOARD IS NOT AVAILABLE ON THIS PLATFORM.');
      return;
    }

    try {
      final item = DataWriterItem();
      if (media.kind == _ClipMediaKind.image) {
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (!mounted) return;
        if (decoded == null) {
          _showFailureNotice('COULD NOT READ IMAGE DATA TO COPY.');
          return;
        }
        item.add(Formats.png(img.encodePng(decoded)));
      } else {
        // Binary video clipboard formats are not universally supported by
        // OS clipboards. A file-URI representation is the real,
        // platform-supported mechanism available here.
        item.add(Formats.fileUri(Uri.file(file.path)));
      }
      await clipboard.write([item]);
      if (!mounted) return;
      _showBriefNotice('COPIED');
    } catch (_) {
      if (mounted) _showFailureNotice('COPY FAILED. PLEASE TRY AGAIN.');
    }
  }

  void _showFailureNotice(String message) {
    final isDark = widget.isDark;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
                border: Border.all(color: widget.borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 11,
                        height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => Navigator.pop(dialogContext),
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      color: isDark ? Colors.white : Colors.black,
                      child: Text(
                        'DISMISS',
                        style: TextStyle(
                            color: isDark ? Colors.black : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
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

  Future<void> _handleCropSave(_ClipMediaRef media, Rect cropRectInImageSpace,
      Size imageSize, int quarterTurns) async {
    try {
      final file = await media.resolveFile();
      if (!mounted) return;
      if (file == null || !await file.exists()) {
        if (mounted) _showFailureNotice('ORIGINAL FILE COULD NOT BE FOUND.');
        return;
      }
      if (!mounted) return;

      final bytes = await file.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (!mounted) return;
      if (decoded == null) {
        _showFailureNotice('COULD NOT DECODE IMAGE FOR CROPPING.');
        return;
      }

      // The crop rectangle was drawn over the image as the user was seeing
      // it (i.e. including any rotation applied in the viewer), so the
      // source image must be rotated the same way before the rect is
      // mapped onto its pixels.
      if (quarterTurns != 0) {
        decoded = img.copyRotate(decoded, angle: 90 * quarterTurns);
      }

      final double scaleX = decoded.width / imageSize.width;
      final double scaleY = decoded.height / imageSize.height;

      final int cropX = (cropRectInImageSpace.left * scaleX)
          .clamp(0, decoded.width - 1)
          .round();
      final int cropY = (cropRectInImageSpace.top * scaleY)
          .clamp(0, decoded.height - 1)
          .round();
      final int cropW = (cropRectInImageSpace.width * scaleX)
          .clamp(1, decoded.width - cropX)
          .round();
      final int cropH = (cropRectInImageSpace.height * scaleY)
          .clamp(1, decoded.height - cropY)
          .round();

      final cropped = img.copyCrop(decoded,
          x: cropX, y: cropY, width: cropW, height: cropH);
      final Uint8List croppedPngBytes =
          Uint8List.fromList(img.encodePng(cropped));

      final String baseName =
          'cropped_${DateTime.now().microsecondsSinceEpoch}.png';

      // Saved into the device's own Pictures/Rocen gallery folder (via
      // MediaStore on Android) rather than the app's private sandbox, so the
      // result is a real, user-visible file the device gallery, file
      // manager, and any other app can all see - not something hidden
      // inside internal app storage.
      final SaveResult saveResult = await SaverGallery.saveImage(
        croppedPngBytes,
        fileName: baseName,
        albumPath: 'Rocen',
        skipIfExists: false,
      );

      if (!mounted) return;

      if (saveResult.savedUri == null) {
        debugPrint('Crop save reported no saved URI: $saveResult');
        _showFailureNotice(
            'CROP SAVE FAILED. THE ORIGINAL FILE WAS NOT CHANGED.');
        return;
      }

      if (!mounted) return;
      _didModifyGallery = true;
      _exitEditMode();
      _showBriefNotice('DONE');
    } catch (e) {
      debugPrint('Crop save exception: $e');
      if (mounted) {
        _showFailureNotice(
            'CROP SAVE FAILED. THE ORIGINAL FILE WAS NOT CHANGED.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final Color bg = isDark ? Colors.black : Colors.white;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              physics: (_isEditMode || _isCropMode || !_showNormalToolbar)
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final media = widget.items[index];
                return _buildMediaLayer(media, index);
              },
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: AnimatedOpacity(
                duration: _editTransitionDuration,
                opacity: _isEditMode ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: _isEditMode,
                  child: GestureDetector(
                    onTap: () {
                      SystemChrome.setEnabledSystemUIMode(
                          SystemUiMode.edgeToEdge);
                      Navigator.pop(
                          context,
                          _ClipViewerResult(
                              lastIndex: _currentIndex,
                              galleryChanged: _didModifyGallery));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: bg,
                        border:
                            Border.all(color: widget.borderColor, width: 0.8),
                      ),
                      child: Text(
                        '[RETURN]',
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.05),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_shouldShowRotateControl())
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: AnimatedOpacity(
                  duration: _editTransitionDuration,
                  opacity: _isEditMode ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: _isEditMode,
                    child: GestureDetector(
                      onTap: () => _rotate(_currentIndex),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: bg,
                          border:
                              Border.all(color: widget.borderColor, width: 0.8),
                        ),
                        child: Text(
                          '[ROTATE]',
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.05),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            _buildAnimatedToolbarStack(),
            if (_showCopiedNotice) _buildCopiedNotice(),
          ],
        ),
      ),
    );
  }

  Widget _buildCopiedNotice() {
    final isDark = widget.isDark;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white : Colors.black,
              border: Border.all(
                  color: isDark ? Colors.black : Colors.white, width: 0.8),
            ),
            child: Text(
              _briefNoticeMessage,
              style: TextStyle(
                color: isDark ? Colors.black : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.08,
              ),
            ),
          ),
        ),
      ),
    );
  }

  final Map<int, Future<File?>> _resolvedFileFutures = {};

  Widget _buildMediaLayer(_ClipMediaRef media, int index) {
    final isDark = widget.isDark;
    final Future<File?> fileFuture =
        _resolvedFileFutures.putIfAbsent(index, () => media.resolveFile());
    return FutureBuilder<File?>(
      future: fileFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? Colors.white : Colors.black),
            ),
          );
        }
        final file = snapshot.data!;

        if (media.kind == _ClipMediaKind.video) {
          return _buildVideoLayer(file, index);
        }
        return _buildImageLayer(file, index);
      },
    );
  }

  Widget _buildImageLayer(File file, int index) {
    final isDark = widget.isDark;
    final int quarterTurns = _rotationFor(index);

    if (_isCropMode && index == _currentIndex) {
      return _CropOverlay(
        key: ValueKey('crop_overlay_$index'),
        file: file,
        isDark: isDark,
        borderColor: widget.borderColor,
        quarterTurns: quarterTurns,
        toolbarHeight: _toolbarHeight,
        onCancel: () => setState(() => _isCropMode = false),
        onConfirm: (rect, imageSize) =>
            _handleCropSave(widget.items[index], rect, imageSize, quarterTurns),
      );
    }

    return GestureDetector(
      onTap: _toggleToolbarVisibility,
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: () => _handleDoubleTap(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: isDark ? Colors.black : Colors.white,
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: InteractiveViewer(
            transformationController: _transformFor(index),
            maxScale: 4.0,
            panEnabled: !_showNormalToolbar,
            scaleEnabled: !_showNormalToolbar,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.items[index].placeholderBytes != null)
                  Image.memory(
                    widget.items[index].placeholderBytes!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                Image.file(
                  file,
                  key: ValueKey('${widget.items[index].id}_${file.path}'),
                  fit: BoxFit.contain,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                    if (wasSynchronouslyLoaded) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoLayer(File file, int index) {
    final isDark = widget.isDark;
    return FutureBuilder<VideoPlayerController>(
      future: _videoControllerFor(index, file),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return Container(
            color: isDark ? Colors.black : Colors.white,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.white : Colors.black),
              ),
            ),
          );
        }
        final controller = snapshot.data!;
        return GestureDetector(
          onTap: _toggleToolbarVisibility,
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: isDark ? Colors.black : Colors.white,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, child) {
                final bool isPlaying = value.isPlaying;
                final bool isAtEnd = value.duration > Duration.zero &&
                    value.position >= value.duration;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: RotatedBox(
                        quarterTurns: _rotationFor(index),
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio == 0
                              ? 16 / 9
                              : value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: (isPlaying && !isAtEnd) ? 0.0 : 1.0,
                      child: IgnorePointer(
                        ignoring: isPlaying && !isAtEnd,
                        child: GestureDetector(
                          onTap: () {
                            if (isAtEnd) {
                              controller.seekTo(Duration.zero);
                              controller.play();
                            } else if (isPlaying) {
                              controller.pause();
                            } else {
                              controller.play();
                            }
                          },
                          child: Icon(
                            isAtEnd
                                ? Icons.replay
                                : (isPlaying
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline),
                            color: Colors.white,
                            size: 56,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: _toolbarHeight + 8,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: EdgeInsets.zero,
                          colors: VideoProgressColors(
                            playedColor: isDark ? Colors.white : Colors.black,
                            bufferedColor:
                                (isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.3),
                            backgroundColor:
                                (isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedToolbarStack() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Stack(
        children: [
          AnimatedSlide(
            offset: _showNormalToolbar ? Offset.zero : const Offset(0, 1),
            duration: _editTransitionDuration,
            curve: Curves.fastOutSlowIn,
            child: _buildNormalToolbar(),
          ),
          AnimatedSlide(
            offset: _isEditMode ? Offset.zero : const Offset(0, 1),
            duration: _editTransitionDuration,
            curve: Curves.fastOutSlowIn,
            child: _buildEditToolbar(),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalToolbar() {
    final isDark = widget.isDark;
    final media = widget.items[_currentIndex];
    final bg = isDark ? Colors.black : Colors.white;
    final iconColor = isDark ? Colors.white : Colors.black;
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      color: bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: _toolbarHeight,
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                  top: BorderSide(color: widget.borderColor, width: 0.8)),
            ),
            child: FutureBuilder<bool>(
              future: widget.actions.isLiked(media),
              builder: (context, likedSnapshot) {
                final bool isLiked = likedSnapshot.data ?? false;
                return Row(
                  children: [
                    _toolbarAction(
                      label: 'SHARE',
                      icon: Icons.share,
                      color: iconColor,
                      onTap: () async {
                        final file = await media.resolveFile();
                        if (file != null) {
                          await SharePlus.instance
                              .share(ShareParams(files: [XFile(file.path)]));
                        }
                      },
                    ),
                    _toolbarAction(
                      label: 'EDIT',
                      icon: Icons.tune,
                      color: iconColor,
                      onTap: _enterEditMode,
                    ),
                    _toolbarAction(
                      label: 'LIKE',
                      icon: isLiked ? Icons.favorite : Icons.favorite_border,
                      color: iconColor,
                      onTap: () async {
                        await widget.actions.toggleLike(media);
                        if (mounted) setState(() {});
                      },
                    ),
                    _toolbarAction(
                      label: 'BIN',
                      icon: Icons.delete_outline,
                      color: Colors.red[400]!,
                      onTap: () => _confirmDelete(media),
                    ),
                    _toolbarAction(
                      label: 'COPY',
                      icon: Icons.copy,
                      color: iconColor,
                      onTap: () => _handleCopy(media),
                    ),
                  ],
                );
              },
            ),
          ),
          if (bottomInset > 0) SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  Widget _toolbarAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: _toolbarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.03),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditToolbar() {
    final isDark = widget.isDark;
    final bg = isDark ? Colors.black : Colors.white;
    final iconColor = isDark ? Colors.white : Colors.black;
    final media = widget.items[_currentIndex];
    final bool isVideo = media.kind == _ClipMediaKind.video;
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      color: bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: _toolbarHeight,
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                  top: BorderSide(color: widget.borderColor, width: 0.8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: isVideo
                        ? null
                        : () => setState(() => _isCropMode = true),
                    child: SizedBox(
                      height: _toolbarHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.crop,
                              color: isVideo
                                  ? iconColor.withValues(alpha: 0.3)
                                  : iconColor,
                              size: 18),
                          const SizedBox(height: 2),
                          Text(
                            'CROP',
                            style: TextStyle(
                                color: isVideo
                                    ? iconColor.withValues(alpha: 0.3)
                                    : iconColor,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.03),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _exitEditMode(),
                    child: SizedBox(
                      height: _toolbarHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, color: iconColor, size: 18),
                          const SizedBox(height: 2),
                          Text(
                            'SAVE',
                            style: TextStyle(
                                color: iconColor,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.03),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (bottomInset > 0) SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  void _confirmDelete(_ClipMediaRef media) {
    final isDark = widget.isDark;
    final Color bg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final Color textMain = isDark ? Colors.white : Colors.black;
    final Color textSub =
        isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(color: widget.borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.actions.deleteConfirmTitle,
                      style: TextStyle(
                          color: textMain,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(
                    widget.actions.deleteConfirmMessage,
                    style: TextStyle(color: textSub, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(dialogContext),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              border: Border.all(
                                  color: widget.borderColor, width: 0.8)),
                          child: Text('CANCEL',
                              style: TextStyle(
                                  color: textMain,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          await widget.actions.delete(media);
                          if (mounted) {
                            Navigator.pop(
                                context,
                                _ClipViewerResult(
                                    lastIndex: _currentIndex,
                                    galleryChanged: true));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.red, width: 0.8)),
                          child: const Text('DELETE',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Interactive crop selection over a static image. Works purely in the
/// widget's own displayed-image coordinate space; the caller maps the
/// resulting rect back to source-pixel coordinates.
class _CropOverlay extends StatefulWidget {
  final File file;
  final bool isDark;
  final Color borderColor;
  final int quarterTurns;
  final double toolbarHeight;
  final VoidCallback onCancel;
  final void Function(Rect cropRect, Size imageDisplaySize) onConfirm;

  const _CropOverlay({
    super.key,
    required this.file,
    required this.isDark,
    required this.borderColor,
    required this.quarterTurns,
    required this.toolbarHeight,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  Rect? _cropRect;
  Size? _imageSize;
  bool _hasUserEdited = false;
  late final Future<ui.Image> _decodeFuture = _decodeUiImage(widget.file);

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bool isSideways =
        widget.quarterTurns == 1 || widget.quarterTurns == 3;
    return Container(
      color: isDark ? Colors.black : Colors.white,
      child: FutureBuilder<ui.Image>(
        future: _decodeFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            // Show the actual photo underneath the spinner instead of a
            // bare black screen - the file is already decoded and cached
            // by the normal viewer's Image.file, so this is just waiting
            // on this overlay's own dimension lookup, not a real reload.
            return Stack(
              fit: StackFit.expand,
              children: [
                RotatedBox(
                  quarterTurns: widget.quarterTurns,
                  child: Image.file(widget.file, fit: BoxFit.contain),
                ),
                Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.white : Colors.black),
                  ),
                ),
              ],
            );
          }
          final uiImage = snapshot.data!;
          // The crop rect the user draws is in the ON-SCREEN (post-rotation)
          // orientation, so when the media is displayed sideways, swap the
          // dimensions used to compute the fitted display size here too.
          final Size naturalSize = isSideways
              ? Size(uiImage.height.toDouble(), uiImage.width.toDouble())
              : Size(uiImage.width.toDouble(), uiImage.height.toDouble());

          return LayoutBuilder(
            builder: (context, constraints) {
              final Size boxSize =
                  Size(constraints.maxWidth, constraints.maxHeight);
              final double scale = math.min(boxSize.width / naturalSize.width,
                  boxSize.height / naturalSize.height);
              final Size displaySize =
                  Size(naturalSize.width * scale, naturalSize.height * scale);

              // The crop overlay's first build can land mid-animation (the
              // edit toolbar is still sliding in), when LayoutBuilder can
              // briefly report a not-yet-settled size. Recompute the default
              // rect until the user actually starts dragging (_hasUserEdited),
              // instead of locking onto whatever the very first build saw.
              if (!_hasUserEdited || _imageSize != displaySize) {
                _imageSize = displaySize;
                _cropRect = Rect.fromLTWH(
                    displaySize.width * 0.1,
                    displaySize.height * 0.1,
                    displaySize.width * 0.8,
                    displaySize.height * 0.8);
              }

              return Stack(
                children: [
                  Center(
                    child: SizedBox(
                      width: displaySize.width,
                      height: displaySize.height,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: SizedBox(
                                width: isSideways
                                    ? displaySize.height
                                    : displaySize.width,
                                height: isSideways
                                    ? displaySize.width
                                    : displaySize.height,
                                child: RotatedBox(
                                  quarterTurns: widget.quarterTurns,
                                  child:
                                      Image.file(widget.file, fit: BoxFit.fill),
                                ),
                              ),
                            ),
                          ),
                          _CropRectHandle(
                            rect: _cropRect!,
                            bounds: Offset.zero & displaySize,
                            borderColor:
                                widget.isDark ? Colors.white : Colors.black,
                            onChanged: (rect) => setState(() {
                              _hasUserEdited = true;
                              _cropRect = rect;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: widget.toolbarHeight + 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: widget.onCancel,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black : Colors.white,
                                border: Border.all(
                                    color: widget.borderColor, width: 0.8),
                              ),
                              alignment: Alignment.center,
                              child: Text('CANCEL',
                                  style: TextStyle(
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                widget.onConfirm(_cropRect!, _imageSize!),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              alignment: Alignment.center,
                              child: Text('CONFIRM CROP',
                                  style: TextStyle(
                                      color:
                                          isDark ? Colors.black : Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<ui.Image> _decodeUiImage(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

/// Draggable/resizable crop rectangle drawn over the image.
class _CropRectHandle extends StatelessWidget {
  final Rect rect;
  final Rect bounds;
  final Color borderColor;
  final void Function(Rect) onChanged;

  static const double _handleSize = 20.0;

  const _CropRectHandle({
    required this.rect,
    required this.bounds,
    required this.borderColor,
    required this.onChanged,
  });

  static const double _minCropSize = 40.0;

  Rect _clampToBounds(Rect r) {
    // Normalize first in case a corner was dragged past its opposite edge,
    // then clamp each edge to the bounds independently so any corner can be
    // the one moving without ever producing an inverted or undersized rect.
    final Rect normalized = Rect.fromLTRB(
      math.min(r.left, r.right),
      math.min(r.top, r.bottom),
      math.max(r.left, r.right),
      math.max(r.top, r.bottom),
    );

    double left =
        normalized.left.clamp(bounds.left, bounds.right - _minCropSize);
    double top = normalized.top.clamp(bounds.top, bounds.bottom - _minCropSize);
    double right = normalized.right.clamp(left + _minCropSize, bounds.right);
    double bottom = normalized.bottom.clamp(top + _minCropSize, bounds.bottom);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dim everything outside the crop rect.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CropDimPainter(rect: rect),
            ),
          ),
        ),
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              final moved = rect.shift(details.delta);
              onChanged(_clampToBounds(moved));
            },
            child: Container(
              // Fully transparent but still opaque to hit-testing (via
              // HitTestBehavior.opaque above), so dragging works from
              // anywhere inside the rect, not just its drawn border.
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(color: borderColor, width: 1.5),
              ),
            ),
          ),
        ),
        _buildCornerHandle(
          left: rect.left - _handleSize / 2,
          top: rect.top - _handleSize / 2,
          onDrag: (delta) => Rect.fromLTRB(
            rect.left + delta.dx,
            rect.top + delta.dy,
            rect.right,
            rect.bottom,
          ),
        ),
        _buildCornerHandle(
          left: rect.right - _handleSize / 2,
          top: rect.top - _handleSize / 2,
          onDrag: (delta) => Rect.fromLTRB(
            rect.left,
            rect.top + delta.dy,
            rect.right + delta.dx,
            rect.bottom,
          ),
        ),
        _buildCornerHandle(
          left: rect.left - _handleSize / 2,
          top: rect.bottom - _handleSize / 2,
          onDrag: (delta) => Rect.fromLTRB(
            rect.left + delta.dx,
            rect.top,
            rect.right,
            rect.bottom + delta.dy,
          ),
        ),
        _buildCornerHandle(
          left: rect.right - _handleSize / 2,
          top: rect.bottom - _handleSize / 2,
          onDrag: (delta) => Rect.fromLTRB(
            rect.left,
            rect.top,
            rect.right + delta.dx,
            rect.bottom + delta.dy,
          ),
        ),
      ],
    );
  }

  Widget _buildCornerHandle({
    required double left,
    required double top,
    required Rect Function(Offset delta) onDrag,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: _handleSize,
      height: _handleSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          onChanged(_clampToBounds(onDrag(details.delta)));
        },
        child: Container(
          decoration: BoxDecoration(
            color: borderColor,
            border: Border.all(
                color:
                    borderColor == Colors.white ? Colors.black : Colors.white,
                width: 1),
          ),
        ),
      ),
    );
  }
}

class _CropDimPainter extends CustomPainter {
  final Rect rect;
  _CropDimPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CropDimPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

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

final gridColumnsProvider =
    NotifierProvider<GridColumnsNotifier, int>(GridColumnsNotifier.new);

class ClipboardScreen extends ConsumerStatefulWidget {
  const ClipboardScreen({super.key});

  @override
  ConsumerState<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends ConsumerState<ClipboardScreen> {
  final PageController _pageController = PageController(initialPage: 0);
  int _activePageIndex = 0;

  final List<AssetEntity> _galleryAssets = [];
  bool _isLoadingGallery = false;
  bool _isLoadingMoreGallery = false;
  AssetPathEntity? _currentAlbum;
  int _galleryTotalCount = 0;
  static const int _galleryPageSize = 90;
  final ScrollController _galleryScrollController = ScrollController();

  final Map<String, Uint8List> _thumbnailCache = {};
  final Set<String> _loadingIds = {};

  bool _isSelectMode = false;
  final Set<String> _selectedGalleryIds = {};
  final Set<String> _selectedImportedIds = {};

  @override
  void initState() {
    super.initState();
    _galleryScrollController.addListener(_onGalleryScroll);
    _fetchInitialGalleryWindow();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _galleryScrollController.removeListener(_onGalleryScroll);
    _galleryScrollController.dispose();
    super.dispose();
  }

  void _onGalleryScroll() {
    if (!_galleryScrollController.hasClients) return;
    final position = _galleryScrollController.position;
    // Start loading the next window a bit before the user actually hits the
    // bottom, so scrolling stays smooth instead of pausing at the edge.
    if (position.pixels >= position.maxScrollExtent - 600) {
      _fetchNextGalleryWindow();
    }
  }

  void _switchTab(int index) {
    setState(() {
      _activePageIndex = index;
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

  void _showAcknowledgeDialog(String title, String message) {
    final isDark = ref.read(themeProvider);
    final Color bg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final Color textMain = isDark ? Colors.white : Colors.black;
    final Color textSub =
        isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252);
    final Color dialogBorderColor =
        isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final Color buttonBg = isDark ? Colors.white : Colors.black;
    final Color buttonText = isDark ? Colors.black : Colors.white;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(color: dialogBorderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: textMain,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textSub, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () => Navigator.pop(dialogContext),
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      color: buttonBg,
                      child: Text(
                        'ACKNOWLEDGE',
                        style: TextStyle(
                            color: buttonText,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
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

  Future<void> _fetchInitialGalleryWindow() async {
    if (_isLoadingGallery) return;
    setState(() => _isLoadingGallery = true);

    try {
      if (_currentAlbum == null) {
        final PermissionState permission =
            await PhotoManager.requestPermissionExtend();
        if (permission.isAuth || permission.hasAccess) {
          final List<AssetPathEntity> albums =
              await PhotoManager.getAssetPathList(
            type: RequestType.common,
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
          if (mounted) {
            _showAcknowledgeDialog('PERMISSION DENIED',
                'MEDIA ACCESS PERMISSION WAS DENIED. GRANT ACCESS TO VIEW YOUR DEVICE GALLERY.');
          }
          setState(() => _isLoadingGallery = false);
          return;
        }
      }

      if (_currentAlbum != null) {
        _galleryTotalCount = await _currentAlbum!.assetCountAsync;

        // Only the first window is fetched eagerly - this is what makes
        // opening the tab fast even with thousands of items in the library.
        final int windowEnd = _galleryPageSize < _galleryTotalCount
            ? _galleryPageSize
            : _galleryTotalCount;
        final List<AssetEntity> firstWindow =
            await _currentAlbum!.getAssetListRange(start: 0, end: windowEnd);

        if (!mounted) return;
        setState(() {
          _galleryAssets.clear();
          _galleryAssets.addAll(firstWindow);
        });

        _preloadTopThumbnails(firstWindow);
      }
    } catch (e) {
      debugPrint('Media registry processing exception: $e');
    } finally {
      if (mounted) setState(() => _isLoadingGallery = false);
    }
  }

  Future<void> _fetchNextGalleryWindow() async {
    if (_isLoadingGallery ||
        _isLoadingMoreGallery ||
        _currentAlbum == null ||
        _galleryAssets.length >= _galleryTotalCount) {
      return;
    }
    setState(() => _isLoadingMoreGallery = true);

    try {
      final int start = _galleryAssets.length;
      final int end = (start + _galleryPageSize) > _galleryTotalCount
          ? _galleryTotalCount
          : start + _galleryPageSize;
      final List<AssetEntity> nextWindow =
          await _currentAlbum!.getAssetListRange(start: start, end: end);

      if (!mounted) return;
      setState(() {
        _galleryAssets.addAll(nextWindow);
      });
      _preloadTopThumbnails(nextWindow);
    } catch (e) {
      debugPrint('Media registry pagination exception: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMoreGallery = false);
    }
  }

  void _preloadTopThumbnails(List<AssetEntity> assets) {
    final int targetPreloadCount = assets.length > 150 ? 150 : assets.length;
    for (int i = 0; i < targetPreloadCount; i++) {
      _loadSingleThumbnail(assets[i]);
    }
  }

  void _loadSingleThumbnail(AssetEntity asset) {
    if (_thumbnailCache.containsKey(asset.id) ||
        _loadingIds.contains(asset.id)) {
      return;
    }
    _loadingIds.add(asset.id);

    asset
        .thumbnailDataWithSize(const ThumbnailSize(360, 360),
            format: ThumbnailFormat.png)
        .then((data) {
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
      _galleryTotalCount = 0;
    });
    await _fetchInitialGalleryWindow();
  }

  Future<void> _importSelectedMedia() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'jpg',
            'jpeg',
            'png',
            'gif',
            'bmp',
            'webp',
            'heic',
            'mp4',
            'mov',
            'm4v',
            '3gp',
            'webm',
            'mkv',
          ],
          allowMultiple: true);

      if (result != null) {
        final List<String> chosenPaths =
            result.paths.whereType<String>().toList();
        if (chosenPaths.isNotEmpty) {
          await ref
              .read(localDatabaseProvider.notifier)
              .insertMultipleItems(chosenPaths, 'imported_clip');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ERROR: ${e.toString().toUpperCase()}')));
      }
    }
  }

  Future<void> _handleBulkDelete() async {
    final bool hasSelection = _activePageIndex == 0
        ? _selectedGalleryIds.isNotEmpty
        : _selectedImportedIds.isNotEmpty;
    if (!hasSelection) {
      _showAcknowledgeDialog(
          'NO SELECTION', 'SELECT AT LEAST 1 MEDIA TO CONTINUE.');
      return;
    }

    if (_activePageIndex == 0) {
      try {
        final List<String> result = await PhotoManager.editor
            .deleteWithIds(_selectedGalleryIds.toList());
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
    final bool hasSelection = _activePageIndex == 0
        ? _selectedGalleryIds.isNotEmpty
        : _selectedImportedIds.isNotEmpty;
    if (!hasSelection) {
      _showAcknowledgeDialog(
          'NO SELECTION', 'SELECT AT LEAST 1 MEDIA TO CONTINUE.');
      return;
    }

    if (_activePageIndex == 0) {
      List<String> pathsToInsert = [];
      for (final id in _selectedGalleryIds) {
        final asset = _galleryAssets.firstWhere((e) => e.id == id,
            orElse: () => _galleryAssets.first);
        final file = await asset.file;
        if (file != null) pathsToInsert.add(file.path);
      }
      if (pathsToInsert.isNotEmpty) {
        await ref
            .read(localDatabaseProvider.notifier)
            .insertMultipleItems(pathsToInsert, 'imported_clip');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('ADDED ${pathsToInsert.length} REFS TO IMPORTED TAB')));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('MEDIA ALREADY PERSISTED INSIDE WORKSPACE')));
      }
    }
    setState(() {
      _selectedGalleryIds.clear();
      _selectedImportedIds.clear();
      _isSelectMode = false;
    });
  }

  Future<void> _handleBulkDislike() async {
    final bool hasSelection = _activePageIndex == 0
        ? _selectedGalleryIds.isNotEmpty
        : _selectedImportedIds.isNotEmpty;
    if (!hasSelection) {
      _showAcknowledgeDialog(
          'NO SELECTION', 'SELECT AT LEAST 1 MEDIA TO CONTINUE.');
      return;
    }

    final allItems = ref.read(localDatabaseProvider);
    int counter = 0;

    if (_activePageIndex == 0) {
      for (final id in _selectedGalleryIds) {
        final asset = _galleryAssets.firstWhere((e) => e.id == id,
            orElse: () => _galleryAssets.first);
        final file = await asset.file;
        if (file != null) {
          final matches = allItems
              .where((e) => e.type == 'imported_clip' && e.content == file.path)
              .toList();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('REMOVED $counter REFS FROM WORKSPACE MATCHES')));
    }
    setState(() {
      _selectedGalleryIds.clear();
      _selectedImportedIds.clear();
      _isSelectMode = false;
    });
  }

  Future<void> _openGalleryViewer(int initialIndex, List<AssetEntity> assets,
      bool isDark, Color borderColor) async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final List<_ClipMediaRef> mediaRefs = assets
        .map(
            (a) => _ClipMediaRef.fromAsset(a, thumbnail: _thumbnailCache[a.id]))
        .toList();

    final actions = _ClipViewerActions(
      isLiked: (media) async {
        final asset = assets.firstWhere((a) => a.id == media.id);
        final file = await asset.file;
        if (file == null) return false;
        final allItems = ref.read(localDatabaseProvider);
        return allItems
            .any((e) => e.type == 'imported_clip' && e.content == file.path);
      },
      toggleLike: (media) async {
        final asset = assets.firstWhere((a) => a.id == media.id);
        final file = await asset.file;
        if (file == null) return;
        final allCurrentItems = ref.read(localDatabaseProvider);
        CaptureItem? existingItem;
        for (final item in allCurrentItems) {
          if (item.type == 'imported_clip' && item.content == file.path) {
            existingItem = item;
            break;
          }
        }
        if (existingItem != null) {
          await ref
              .read(localDatabaseProvider.notifier)
              .deleteItem(existingItem.id);
        } else {
          await ref
              .read(localDatabaseProvider.notifier)
              .insertMultipleItems([file.path], 'imported_clip');
        }
      },
      delete: (media) async {
        final asset = assets.firstWhere((a) => a.id == media.id);
        try {
          final List<String> result =
              await PhotoManager.editor.deleteWithIds([asset.id]);
          if (result.isNotEmpty) {
            _refreshGallery();
          }
        } catch (e) {
          debugPrint('Native deletion exception: $e');
        }
      },
      deleteConfirmTitle: 'DELETE IMAGE',
      deleteConfirmMessage:
          'ARE YOU SURE YOU WANT TO DELETE THIS IMAGE FROM YOUR DEVICE CORES?',
    );

    final result = await Navigator.push<_ClipViewerResult>(
      context,
      MaterialPageRoute(
        builder: (context) => _ClipMediaViewer(
          items: mediaRefs,
          initialIndex: initialIndex,
          isDark: isDark,
          borderColor: borderColor,
          actions: actions,
        ),
      ),
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Cropping while viewing saves a new image into the device gallery, and
    // deleting removes one - refresh only when the viewer reports one of
    // those actually happened, so a plain browse-and-return doesn't pay for
    // a full gallery re-fetch.
    if (mounted && (result?.galleryChanged ?? false)) {
      await _refreshGallery();
    }
  }

  Future<void> _openImportedViewer(int initialIndex, List<CaptureItem> items,
      bool isDark, Color borderColor) async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final List<_ClipMediaRef> mediaRefs =
        items.map((i) => _ClipMediaRef.fromCaptureItem(i)).toList();

    final actions = _ClipViewerActions(
      isLiked: (media) async {
        final allItems = ref.read(localDatabaseProvider);
        return allItems.any((e) =>
            e.type == 'imported_clip' &&
            e.content == items.firstWhere((i) => i.id == media.id).content);
      },
      toggleLike: (media) async {
        final currentItem = items.firstWhere((i) => i.id == media.id);
        final filePath = currentItem.content;
        final allCurrentItems = ref.read(localDatabaseProvider);
        CaptureItem? existingItem;
        for (final dItem in allCurrentItems) {
          if (dItem.type == 'imported_clip' && dItem.content == filePath) {
            existingItem = dItem;
            break;
          }
        }
        if (existingItem != null) {
          await ref
              .read(localDatabaseProvider.notifier)
              .deleteItem(existingItem.id);
        } else {
          await ref
              .read(localDatabaseProvider.notifier)
              .insertMultipleItems([filePath], 'imported_clip');
        }
      },
      delete: (media) async {
        final currentItem = items.firstWhere((i) => i.id == media.id);
        try {
          final file = File(currentItem.content);
          if (await file.exists()) {
            await file.delete();
          }
          await ref
              .read(localDatabaseProvider.notifier)
              .deleteItem(currentItem.id);
        } catch (e) {
          debugPrint('Local file deletion error: $e');
        }
      },
      deleteConfirmTitle: 'DELETE IMAGE',
      deleteConfirmMessage:
          'ARE YOU SURE YOU WANT TO WIPE THIS REFS MATRIX OUT OF THE APPLICATION PERSISTENT STORAGE AND DISK DEVICE MEMORY?',
    );

    await Navigator.push<_ClipViewerResult>(
      context,
      MaterialPageRoute(
        builder: (context) => _ClipMediaViewer(
          items: mediaRefs,
          initialIndex: initialIndex,
          isDark: isDark,
          borderColor: borderColor,
          actions: actions,
        ),
      ),
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // No manual refresh needed here: deletions from this tab already go
    // through localDatabaseProvider, which the imported grid watches
    // directly, and a crop taken from this tab saves into the device
    // gallery (a different tab entirely, refreshed independently there).
  }

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
          valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? Colors.white : Colors.black),
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

    return Column(
      children: [
        Expanded(
          child: MasonryGridView.count(
            controller: _galleryScrollController,
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
              final double calculatedRatio =
                  (nativeWidth > 0 && nativeHeight > 0)
                      ? (nativeWidth / nativeHeight)
                      : 1.0;

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
                    : () =>
                        _openGalleryViewer(index, assets, isDark, borderColor),
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
                                ? Container(
                                    color: isDark ? Colors.black : Colors.white,
                                    child: Image.memory(
                                      cachedBytes,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      gaplessPlayback: true,
                                    ),
                                  )
                                : Container(
                                    color: containerBg,
                                  ),
                          ),
                        ],
                      ),
                    ),
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
                    if (asset.type == AssetType.video)
                      const Positioned(
                        left: 8,
                        bottom: 8,
                        child: Icon(Icons.play_circle_outline,
                            color: Colors.white, size: 18),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_isLoadingMoreGallery)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? Colors.white : Colors.black),
                ),
              ),
            ),
          ),
      ],
    );
  }

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
                style: TextStyle(
                    color: textSub,
                    fontSize: 11.5,
                    height: 1.6,
                    letterSpacing: 0.03),
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
                      border: Border.all(color: textMain, width: 0.8)),
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
        final bool isVideoItem = _ClipMediaRef._isVideoPath(item.content);

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
              : () => _openImportedViewer(index, items, isDark, borderColor),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 0.8),
                    color: containerBg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: isDark ? Colors.black : Colors.white,
                      child: isVideoItem
                          ? Container(
                              color: containerBg,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(24),
                              child: Icon(Icons.movie_outlined,
                                  color: textSub, size: 22),
                            )
                          : Image.file(
                              File(item.content),
                              key: ValueKey(
                                  '${item.content}_${item.timestamp.microsecondsSinceEpoch}'),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                    padding: const EdgeInsets.all(12),
                                    child: Text('BROKEN REF',
                                        style: TextStyle(
                                            color: Colors.red[400],
                                            fontSize: 9)));
                              },
                            ),
                    ),
                    if (columns <= 2)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                            border: Border(
                                top: BorderSide(
                                    color: borderColor, width: 0.8))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () => ref
                                  .read(localDatabaseProvider.notifier)
                                  .deleteItem(item.id),
                              child:
                                  Icon(Icons.close, color: textSub, size: 12),
                            )
                          ],
                        ),
                      ),
                  ],
                ),
              ),
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
              if (isVideoItem)
                const Positioned(
                  left: 8,
                  bottom: 8,
                  child: Icon(Icons.play_circle_outline,
                      color: Colors.white, size: 18),
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

    final importedItems = allItems
        .where((e) => e.type == 'imported_clip')
        .toList()
        .reversed
        .toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    final borderColor =
        isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final containerBg =
        isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEEEEEE);

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
                style: TextStyle(
                    color: textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.02),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_isSelectMode) {
                        _handleBulkDelete();
                      } else {
                        _activePageIndex == 0
                            ? _refreshGallery()
                            : _importSelectedMedia();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: _isSelectMode
                                  ? Colors.red.shade400
                                  : borderColor,
                              width: 0.8),
                          color: _isSelectMode
                              ? Colors.red.withValues(alpha: 0.1)
                              : (isDark ? Colors.white : Colors.black)),
                      child: Text(
                        _isSelectMode
                            ? 'DELETE'
                            : (_activePageIndex == 0 ? 'REFRESH' : 'IMPORT'),
                        style: TextStyle(
                            color: _isSelectMode
                                ? Colors.red.shade400
                                : (isDark ? Colors.black : Colors.white),
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          border: Border.all(color: borderColor, width: 0.8),
                          color: containerBg),
                      child: Text(
                        _isSelectMode ? 'UNDO' : 'SELECT',
                        style: TextStyle(
                            color: textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      if (_isSelectMode) {
                        _handleBulkLike();
                      } else {
                        ref
                            .read(gridColumnsProvider.notifier)
                            .makeItemsLarger();
                      }
                    },
                    child: Container(
                      padding: _isSelectMode
                          ? const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4)
                          : const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          border: Border.all(color: borderColor, width: 0.8),
                          color: containerBg),
                      child: _isSelectMode
                          ? Icon(Icons.favorite, color: textMain, size: 14)
                          : Text('+',
                              style: TextStyle(
                                  color: textMain,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      if (_isSelectMode) {
                        _handleBulkDislike();
                      } else {
                        ref
                            .read(gridColumnsProvider.notifier)
                            .makeItemsSmaller();
                      }
                    },
                    child: Container(
                      padding: _isSelectMode
                          ? const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4)
                          : const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                          border: Border.all(color: borderColor, width: 0.8),
                          color: containerBg),
                      child: _isSelectMode
                          ? Icon(Icons.favorite_border,
                              color: textSub, size: 14)
                          : Text('-',
                              style: TextStyle(
                                  color: textMain,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
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
                      border: Border.all(
                          color: _activePageIndex == 0 ? textMain : borderColor,
                          width: _activePageIndex == 0 ? 1.5 : 0.8),
                      color: _activePageIndex == 0
                          ? containerBg
                          : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'ACCESS GALLERY',
                      style: TextStyle(
                          color: _activePageIndex == 0 ? textMain : textSub,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.05),
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
                      border: Border.all(
                          color: _activePageIndex == 1 ? textMain : borderColor,
                          width: _activePageIndex == 1 ? 1.5 : 0.8),
                      color: _activePageIndex == 1
                          ? containerBg
                          : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'IMPORT MEDIA',
                      style: TextStyle(
                          color: _activePageIndex == 1 ? textMain : textSub,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.05),
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
              onPageChanged: (index) =>
                  setState(() => _activePageIndex = index),
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
