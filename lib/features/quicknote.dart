import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../core/debug_log.dart';
import '../main.dart';

class SecurityUiTheme {
  final bool isDark;
  late final Color textMain;
  late final Color textSub;
  late final Color borderColor;
  late final Color dialogBg;
  late final Color ruleBorder;

  SecurityUiTheme(this.isDark) {
    textMain = isDark ? Colors.white : Colors.black;
    textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
  }
}

void showMissingKeyUiDialog(BuildContext context, bool isDark,
    {String? message}) {
  final theme = SecurityUiTheme(isDark);
  final String bodyMessage =
      message ?? 'SET KEY FIRST FROM SETTINGS TO USE THIS FEATURE';
  final Color buttonBg = isDark ? Colors.white : Colors.black;
  final Color buttonText = isDark ? Colors.black : Colors.white;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    pageBuilder: (context, anim1, anim2) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.dialogBg,
              border: Border.all(color: theme.borderColor, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'SECURITY LOCK OUTCAST',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.05),
                ),
                const SizedBox(height: 16),
                Text(
                  bodyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 12,
                      height: 1.5,
                      letterSpacing: 0.02,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: buttonBg,
                    child: Text('ACKNOWLEDGE',
                        style: TextStyle(
                            color: buttonText,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
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

void showAcknowledgeDialog(
    BuildContext context, bool isDark, String title, String message) {
  final theme = SecurityUiTheme(isDark);
  final Color buttonBg = isDark ? Colors.white : Colors.black;
  final Color buttonText = isDark ? Colors.black : Colors.white;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    pageBuilder: (context, anim1, anim2) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.dialogBg,
              border: Border.all(color: theme.borderColor, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.05),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 12,
                      height: 1.5,
                      letterSpacing: 0.02,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: buttonBg,
                    child: Text('ACKNOWLEDGE',
                        style: TextStyle(
                            color: buttonText,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
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

class GithubSyncGateResult {
  final bool allowed;
  final String blockedReason;
  const GithubSyncGateResult._(this.allowed, this.blockedReason);

  static const GithubSyncGateResult blocked = GithubSyncGateResult._(
    false,
    'SECURE NOTE/BACKUP SYNC IS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE IS IMPLEMENTED. NO LEGACY OR TEMPORARY CIPHERTEXT IS READ OR WRITTEN.',
  );
}

Future<GithubSyncGateResult> isGithubSyncCurrentlyAllowed() async =>
    GithubSyncGateResult.blocked;

Future<bool> attemptGithubSync(
  WidgetRef ref, {
  Map<String, String>? upsert,
}) async {
  secureDebugLog('GITHUB NOTE SYNC BLOCKED: Stage 6 ciphertext envelope is not present.');
  return false;
}

Future<String?> pushAllBackupEnabledNotes(WidgetRef ref) async =>
    GithubSyncGateResult.blocked.blockedReason;

Future<void> performRefresh(
  WidgetRef ref,
  BuildContext context, {
  bool silent = false,
  void Function(String phase)? onPhase,
}) async {
  onPhase?.call('REFRESH');
  if (!silent && context.mounted) {
    final isDark = ref.read(themeProvider);
    showAcknowledgeDialog(
      context,
      isDark,
      'BACKUP UNAVAILABLE',
      GithubSyncGateResult.blocked.blockedReason,
    );
  }
}

class QuickNoteScreen extends ConsumerStatefulWidget {
  const QuickNoteScreen({super.key});

  @override
  ConsumerState<QuickNoteScreen> createState() => _QuickNoteScreenState();
}

class _QuickNoteScreenState extends ConsumerState<QuickNoteScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _isNoteLocked = false;
  bool _isBackupEnabled = false;
  Timer? _titleCheckDebounce;
  String? _titleCheckStatus;
  String _refreshLabel = 'REFRESH';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _bodyController = TextEditingController();
    _titleController.addListener(_onTitleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        performRefresh(
          ref,
          context,
          silent: true,
          onPhase: (phase) {
            if (mounted) setState(() => _refreshLabel = phase);
          },
        );
      }
    });
  }

  @override
  void dispose() {
    _titleCheckDebounce?.cancel();
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    _titleCheckDebounce?.cancel();
    final String title = _titleController.text.trim();

    if (!_isBackupEnabled || title.isEmpty) {
      if (_titleCheckStatus != null) setState(() => _titleCheckStatus = null);
      return;
    }

    setState(() => _titleCheckStatus = 'FETCHING');

    _titleCheckDebounce = Timer(const Duration(seconds: 5), () {
      _performTitleCheck(title);
    });
  }

  Future<void> _performTitleCheck(String title) async {
    final bool taken =
        ref.read(localDatabaseProvider.notifier).titleExists(title);
    if (mounted) {
      setState(() => _titleCheckStatus = taken ? 'TAKEN' : 'AVAILABLE');
    }
  }

  Future<void> _compileAndSaveNote() async {
    final String cleanBody = _bodyController.text.trim();
    final String cleanTitle = _titleController.text.trim();
    if (cleanBody.isEmpty) return;

    final isDark = ref.read(themeProvider);
    if (_isNoteLocked || _isBackupEnabled) {
      showAcknowledgeDialog(
        context,
        isDark,
        'SECURE STORAGE UNAVAILABLE',
        'NOTE ENCRYPTION AND GITHUB BACKUP REQUIRE THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE. ROCEN WILL NOT WRITE LEGACY OR TEMPORARY CIPHERTEXT.',
      );
      return;
    }

    final DateTime saveTimestamp = DateTime.now();
    _titleController.clear();
    _bodyController.clear();
    setState(() {
      _isNoteLocked = false;
      _isBackupEnabled = false;
    });
    FocusScope.of(context).unfocus();

    final bool inserted =
        await ref.read(localDatabaseProvider.notifier).insertItem(
              cleanBody,
              'note',
              title: cleanTitle,
              backupEnabled: false,
              remoteFileId: null,
              timestamp: saveTimestamp,
            );

    if (!inserted && mounted) {
      _titleController.text = cleanTitle;
      _bodyController.text = cleanBody;
      showAcknowledgeDialog(
        context,
        isDark,
        'NOTE SAVE BLOCKED',
        'PROTECTED NOTE PERSISTENCE IS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE EXISTS. NO PLAINTEXT OR TEMPORARY CIPHERTEXT WAS WRITTEN.',
      );
    }
  }

  void _showDeleteConfirmation(BuildContext context, String id) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, anim1, anim2) {
        return Consumer(
          builder: (context, ref, child) {
            final isDark = ref.watch(themeProvider);
            final theme = SecurityUiTheme(isDark);
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF121212) : Colors.white,
                    border: Border.all(color: theme.borderColor, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text('PURGE THIS DATA SEGMENT?',
                            style: TextStyle(
                                color: theme.textMain,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.02)),
                      ),
                      Container(height: 0.8, color: theme.borderColor),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                child: Text('CANCEL',
                                    style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFF737373)
                                            : const Color(0xFF888888),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                          Container(
                              width: 0.8, height: 40, color: theme.borderColor),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                if (!protectedApplicationPersistenceAvailable) {
                                  showAcknowledgeDialog(
                                    context,
                                    isDark,
                                    'DELETE BLOCKED',
                                    'PROTECTED NOTE PERSISTENCE IS UNAVAILABLE. THE NOTE WAS NOT DELETED OR CHANGED.',
                                  );
                                  return;
                                }
                                final bool deleted = await ref
                                    .read(localDatabaseProvider.notifier)
                                    .deleteItem(id);
                                if (!deleted) {
                                  if (context.mounted) {
                                    showAcknowledgeDialog(
                                      context,
                                      isDark,
                                      'DELETE NOT SAVED',
                                      'PROTECTED NOTE PERSISTENCE IS UNAVAILABLE. THE NOTE WAS NOT DELETED.',
                                    );
                                  }
                                  return;
                                }
                                if (context.mounted) Navigator.pop(context);
                                unawaited(attemptGithubSync(ref));
                              },
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                child: const Text('DELETE',
                                    style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
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

  void _navigateToEdit(BuildContext context, CaptureItem item) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            EditNoteScreen(item: item),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
      ),
    );
  }

  String _formatCustomDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = (dateTime.year % 100).toString().padLeft(2, '0');
    return '$day/$month/$year';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final items = ref
        .watch(localDatabaseProvider)
        .where((e) => e.type == 'note')
        .toList();
    final theme = SecurityUiTheme(isDark);

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: theme.textMain.withValues(alpha: 0.2),
          selectionHandleColor: theme.textMain,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('QUICK NOTES',
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.02)),
                GestureDetector(
                  onTap: _refreshLabel != 'REFRESH'
                      ? null
                      : () => performRefresh(
                            ref,
                            context,
                            onPhase: (phase) {
                              if (mounted) {
                                setState(() => _refreshLabel = phase);
                              }
                            },
                          ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: theme.textMain),
                    child: Text(
                      _refreshLabel,
                      style: TextStyle(
                        color: isDark ? Colors.black : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    style: TextStyle(
                        color: theme.textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    cursorColor: theme.textMain,
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: TextStyle(
                          color: theme.textSub, fontWeight: FontWeight.w400),
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.only(bottom: 8),
                    ),
                  ),
                ),
                if (_titleCheckStatus != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _titleCheckStatus!,
                    style: TextStyle(
                      color: _titleCheckStatus == 'TAKEN'
                          ? const Color(0xFFEF4444)
                          : (_titleCheckStatus == 'FETCHING'
                              ? theme.textSub
                              : theme.textMain),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.02,
                    ),
                  ),
                ],
              ],
            ),
            Container(height: 1.0, color: const Color(0xFFa6a6a6)),
            const SizedBox(height: 8),
            TextField(
              controller: _bodyController,
              style: TextStyle(color: theme.textMain, fontSize: 13),
              maxLines: 4,
              cursorColor: theme.textMain,
              decoration: InputDecoration(
                hintText: 'Tell me your story',
                hintStyle: TextStyle(color: theme.textSub),
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        showAcknowledgeDialog(
                          context,
                          isDark,
                          'NOTE ENCRYPTION UNAVAILABLE',
                          'THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE HAS NOT BEEN IMPLEMENTED YET. ROCEN WILL NOT CREATE LEGACY OR TEMPORARY CIPHERTEXT.',
                        );
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(
                            _isNoteLocked ? Icons.lock : Icons.lock_open,
                            size: 14,
                            color:
                                _isNoteLocked ? theme.textMain : theme.textSub,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ENCRYPTION',
                            style: TextStyle(
                              color: _isNoteLocked
                                  ? theme.textMain
                                  : theme.textSub,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.02,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: () {
                        showAcknowledgeDialog(
                          context,
                          isDark,
                          'GITHUB BACKUP UNAVAILABLE',
                          'SECURE NOTE BACKUP REMAINS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE IS IMPLEMENTED.',
                        );
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(
                            _isBackupEnabled
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            size: 14,
                            color: _isBackupEnabled
                                ? theme.textMain
                                : theme.textSub,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'BACKUP',
                            style: TextStyle(
                              color: _isBackupEnabled
                                  ? theme.textMain
                                  : theme.textSub,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.02,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _compileAndSaveNote,
                  child: Text('COMMIT',
                      style: TextStyle(
                          color: theme.textMain,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Divider(color: theme.ruleBorder, height: 16, thickness: 0.8),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'NO ACTIVE NOTE REGISTRIES CURRENTLY SAVED',
                        style: TextStyle(
                            color: theme.textSub,
                            fontSize: 11,
                            letterSpacing: 0.05),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final formattedDate = _formatCustomDate(item.timestamp);

                        return GestureDetector(
                          onTap: () => _navigateToEdit(context, item),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: theme.ruleBorder, width: 0.8)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: item.title.isNotEmpty
                                                    ? '${item.title.toUpperCase()}  '
                                                    : 'UNTITLED  ',
                                                style: TextStyle(
                                                  color: theme.textMain,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.02,
                                                ),
                                              ),
                                              if (item.pendingReviewAfterSync)
                                                TextSpan(
                                                  text: '-- UPDATED  ',
                                                  style: TextStyle(
                                                    color: theme.textMain
                                                        .withValues(alpha: 0.7),
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.03,
                                                  ),
                                                ),
                                              TextSpan(
                                                text: formattedDate,
                                                style: TextStyle(
                                                  color: theme.textSub,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      AnimatedClampedText(
                                              text: item.content,
                                              style: TextStyle(
                                                color: isDark
                                                    ? const Color(0xFFA3A3A3)
                                                    : const Color(0xFF404040),
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                              maxLines: 10,
                                            ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _navigateToEdit(context, item),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Icon(Icons.edit_outlined,
                                            color: theme.textSub, size: 18),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => _showDeleteConfirmation(
                                          context, item.id),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Icon(
                                            Icons.delete_outline_rounded,
                                            color: theme.textSub,
                                            size: 20),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}

class AnimatedClampedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int maxLines;

  const AnimatedClampedText({
    super.key,
    required this.text,
    required this.style,
    required this.maxLines,
  });

  @override
  State<AnimatedClampedText> createState() => _AnimatedClampedTextState();
}

class _AnimatedClampedTextState extends State<AnimatedClampedText> {
  late Timer _timer;
  int _dotIndex = 0;
  final List<String> _dotFrames = ['', '.', '..', '...', '..', '.'];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 450), (timer) {
      if (mounted) {
        setState(() {
          _dotIndex = (_dotIndex + 1) % _dotFrames.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final isOverflowing = textPainter.didExceedMaxLines;

        if (!isOverflowing) {
          return Text(widget.text, style: widget.style);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: widget.maxLines,
              overflow: TextOverflow.clip,
              style: widget.style,
            ),
            Container(
              height: 20,
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                _dotFrames[_dotIndex],
                style: widget.style.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class EditNoteScreen extends ConsumerStatefulWidget {
  final CaptureItem item;

  const EditNoteScreen({super.key, required this.item});

  @override
  ConsumerState<EditNoteScreen> createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends ConsumerState<EditNoteScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _isNoteLocked = false;
  bool _isBackupEnabled = false;
  Timer? _debounceTimer;
  Timer? _titleCheckDebounce;
  String? _titleCheckStatus;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _bodyController = TextEditingController(text: widget.item.content);
    _isNoteLocked = false;
    _isBackupEnabled = false;

    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
    _titleController.addListener(_onTitleUniquenessChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleCheckDebounce?.cancel();
    _titleController.removeListener(_onTextChanged);
    _bodyController.removeListener(_onTextChanged);
    _titleController.removeListener(_onTitleUniquenessChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTitleUniquenessChanged() {
    _titleCheckDebounce?.cancel();
    final String title = _titleController.text.trim();
    final String originalTitle = widget.item.title.trim();

    if (!_isBackupEnabled || title.isEmpty || title == originalTitle) {
      if (_titleCheckStatus != null) setState(() => _titleCheckStatus = null);
      return;
    }

    setState(() => _titleCheckStatus = 'FETCHING');

    _titleCheckDebounce = Timer(const Duration(seconds: 5), () {
      _performTitleCheck(title);
    });
  }

  Future<void> _performTitleCheck(String title) async {
    final bool taken = ref
        .read(localDatabaseProvider.notifier)
        .titleExists(title, excludingId: widget.item.id);
    if (mounted) {
      setState(() => _titleCheckStatus = taken ? 'TAKEN' : 'AVAILABLE');
    }
  }

  void _onTextChanged() {
    if (!protectedApplicationPersistenceAvailable) return;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _dynamicSave();
    });
  }

  Future<void> _dynamicSave() async {
    if (!protectedApplicationPersistenceAvailable) return;
    final bool saved = await ref.read(localDatabaseProvider.notifier).updateItem(
          widget.item.id,
          _bodyController.text.trim(),
          title: _titleController.text.trim(),
          backupEnabled: false,
          remoteFileId: null,
        );
    if (!saved && mounted) {
      showAcknowledgeDialog(
        context,
        ref.read(themeProvider),
        'NOTE SAVE BLOCKED',
        'PROTECTED NOTE PERSISTENCE IS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE EXISTS. NO PLAINTEXT OR TEMPORARY CIPHERTEXT WAS WRITTEN.',
      );
    }
  }

  void _toggleLock() {
    final isDark = ref.read(themeProvider);
    showAcknowledgeDialog(
      context,
      isDark,
      'NOTE ENCRYPTION UNAVAILABLE',
      'THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE HAS NOT BEEN IMPLEMENTED YET. THE APP WILL NOT CREATE A LEGACY OR TEMPORARY NOTE CIPHERTEXT.',
    );
  }

  void _toggleBackup() {
    final isDark = ref.read(themeProvider);
    showAcknowledgeDialog(
      context,
      isDark,
      'GITHUB BACKUP UNAVAILABLE',
      'SECURE NOTE BACKUP REMAINS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE IS IMPLEMENTED. GITHUB ACCESS IS STILL AVAILABLE IN SETTINGS FOR MASTER-KEY RECOVERY METADATA.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final theme = SecurityUiTheme(isDark);
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: theme.textMain.withValues(alpha: 0.2),
          selectionHandleColor: theme.textMain,
        ),
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: theme.textMain, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('EDIT NOTE',
              style: TextStyle(
                  color: theme.textMain,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1)),
          actions: [
            IconButton(
              icon: Icon(
                _isNoteLocked ? Icons.lock : Icons.lock_open,
                color: theme.textMain,
                size: 20,
              ),
              onPressed: _toggleLock,
            ),
            IconButton(
              icon: Icon(
                _isBackupEnabled
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                color: theme.textMain,
                size: 20,
              ),
              onPressed: _toggleBackup,
            ),
            TextButton(
              onPressed: () async {
                _debounceTimer?.cancel();
                final String rawBody = _bodyController.text.trim();
                final String cleanTitle = _titleController.text.trim();
                String contentToPersist = rawBody;
                if (!mounted) return;

                _isBackupEnabled = false;

                final DateTime saveTimestamp = DateTime.now();
                final bool success =
                    await ref.read(localDatabaseProvider.notifier).updateItem(
                          widget.item.id,
                          contentToPersist,
                          title: cleanTitle,
                          backupEnabled: false,
                          remoteFileId: null,
                          timestamp: saveTimestamp,
                        );

                if (!success) {
                  if (context.mounted) {
                    showAcknowledgeDialog(
                      context,
                      isDark,
                      'NOTE SAVE BLOCKED',
                      'PROTECTED NOTE PERSISTENCE IS DISABLED UNTIL THE APPROVED STAGE 6 CIPHERTEXT ENVELOPE EXISTS. NO PLAINTEXT OR TEMPORARY CIPHERTEXT WAS WRITTEN.',
                    );
                  }
                  return;
                }

                if (context.mounted) Navigator.pop(context);
              },
              child: Text('SAVE',
                  style: TextStyle(
                      color: theme.textMain,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        style: TextStyle(
                            color: theme.textMain,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                        cursorColor: theme.textMain,
                        decoration: InputDecoration(
                          hintText: 'Title',
                          hintStyle: TextStyle(
                              color: theme.textSub,
                              fontWeight: FontWeight.w400),
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_titleCheckStatus != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _titleCheckStatus!,
                        style: TextStyle(
                          color: _titleCheckStatus == 'TAKEN'
                              ? const Color(0xFFEF4444)
                              : (_titleCheckStatus == 'FETCHING'
                                  ? theme.textSub
                                  : theme.textMain),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.02,
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                    height: 0.8,
                    color: theme.ruleBorder,
                    margin: const EdgeInsets.symmetric(vertical: 12)),
                Expanded(
                  child: TextField(
                    controller: _bodyController,
                    style: TextStyle(
                        color: theme.textMain, fontSize: 14, height: 1.6),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    cursorColor: theme.textMain,
                    decoration: InputDecoration(
                      hintText: 'Note content...',
                      hintStyle: TextStyle(color: theme.textSub),
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}