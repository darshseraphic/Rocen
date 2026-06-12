import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/database.dart';
import '../core/crypto_engine.dart';
import '../main.dart';

class QuickNoteScreen extends ConsumerStatefulWidget {
  const QuickNoteScreen({super.key});

  @override
  ConsumerState<QuickNoteScreen> createState() => _QuickNoteScreenState();
}

class _QuickNoteScreenState extends ConsumerState<QuickNoteScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _isNoteLocked = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _bodyController = TextEditingController();
    _enforceKeyRotationPurge();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _enforceKeyRotationPurge() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsBox = Hive.box('rocen_settings_box');
      final String? currentPin = settingsBox.get('system_crypto_pin');
      final String? lastActivePin = settingsBox.get('last_active_crypto_pin_snapshot');

      if (currentPin != lastActivePin) {
        final currentItems = ref.read(localDatabaseProvider);
        final targetsToPurge = currentItems.where((item) => item.type == 'encrypted_note').toList();

        for (var target in targetsToPurge) {
          ref.read(localDatabaseProvider.notifier).deleteItem(target.id);
        }
        settingsBox.put('last_active_crypto_pin_snapshot', currentPin);
      }
    });
  }

  void _showMissingKeyDialog(bool isDark) {
    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.7),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dialogBg,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SECURITY LOCK OUTCAST',
                    style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SET KEY FIRST FROM SETTING TO USE THIS FEATURE',
                    style: TextStyle(color: textMain, fontSize: 12, height: 1.5, letterSpacing: 0.02, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: borderColor, width: 0.8),
                        ),
                        child: Text('ACKNOWLEDGE', style: TextStyle(color: textMain, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _compileAndSaveNote() async {
    final String cleanBody = _bodyController.text.trim();
    final String cleanTitle = _titleController.text.trim();
    if (cleanBody.isEmpty) return;

    String finalPayload = cleanBody;
    final String? globalPin = Hive.box('rocen_settings_box').get('system_crypto_pin');

    if (_isNoteLocked) {
      if (globalPin == null || globalPin.isEmpty) {
        final isDark = ref.read(themeProvider);
        _showMissingKeyDialog(isDark);
        return;
      }
      finalPayload = CryptoEngine.xorProcess(cleanBody, globalPin);
    }

    await ref.read(localDatabaseProvider.notifier).insertItem(
      finalPayload,
      _isNoteLocked ? 'encrypted_note' : 'note',
      title: cleanTitle,
    );

    _titleController.clear();
    _bodyController.clear();
    setState(() => _isNoteLocked = false);
    FocusScope.of(context).unfocus();

    Hive.box('rocen_settings_box').put('last_active_crypto_pin_snapshot', globalPin);
  }

  void _promptForPinChallenge(CaptureItem item, bool isDark, {bool openForEditing = false}) {
    final String? globalPin = Hive.box('rocen_settings_box').get('system_crypto_pin');

    if (globalPin == null || globalPin.isEmpty) {
      _showMissingKeyDialog(isDark);
      return;
    }

    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final TextEditingController pinVerifyController = TextEditingController();

    bool hasPinFailed = false;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.7),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: dialogBg,
                    border: Border.all(color: borderColor, width: 0.8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          hasPinFailed ? 'INVALID KEY PIN - TRY AGAIN' : 'ENTER 6-DIGIT PIN',
                          style: TextStyle(
                              color: hasPinFailed ? const Color(0xFFEF4444) : textMain,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.05
                          )
                      ),
                      const SizedBox(height: 20),

                      Stack(
                        children: [
                          Opacity(
                            opacity: 0.0,
                            child: TextField(
                              controller: pinVerifyController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              autofocus: true,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (hasPinFailed) {
                                    hasPinFailed = false;
                                  }
                                });
                              },
                              decoration: const InputDecoration(
                                counterText: '',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(6, (index) {
                                final String text = pinVerifyController.text;
                                bool isFilled = text.length > index;
                                bool isCurrentFocus = text.length == index;

                                Color currentBoxBorderColor;
                                if (hasPinFailed) {
                                  currentBoxBorderColor = const Color(0xFFEF4444);
                                } else if (isCurrentFocus) {
                                  currentBoxBorderColor = textMain;
                                } else {
                                  currentBoxBorderColor = isFilled ? textMain.withOpacity(0.6) : borderColor;
                                }

                                return Container(
                                  width: 40,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(
                                      color: currentBoxBorderColor,
                                      width: isCurrentFocus || hasPinFailed ? 1.2 : 0.8,
                                    ),
                                  ),
                                  child: isFilled
                                      ? Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasPinFailed ? const Color(0xFFEF4444) : textMain,
                                    ),
                                  )
                                      : const SizedBox.shrink(),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: borderColor, width: 0.8),
                              ),
                              child: Text('CANCEL', style: TextStyle(color: isDark ? const Color(0xFF888888) : const Color(0xFF525252), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              if (pinVerifyController.text == globalPin) {
                                Navigator.pop(context);
                                if (openForEditing) {
                                  String rawContent = '';
                                  try {
                                    rawContent = CryptoEngine.xorProcess(item.content, globalPin);
                                  } catch (_) {
                                    rawContent = 'DECRYPTION FAULT';
                                  }
                                  final unpackedItem = CaptureItem(
                                    id: item.id,
                                    title: item.title,
                                    content: rawContent,
                                    type: item.type,
                                    timestamp: item.timestamp,
                                  );
                                  _navigateToEdit(context, unpackedItem);
                                } else {
                                  _revealEncryptedNotePayload(item, globalPin, isDark);
                                }
                              } else {
                                setDialogState(() {
                                  hasPinFailed = true;
                                  pinVerifyController.clear();
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(color: textMain),
                              child: Text('VERIFY', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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

  void _revealEncryptedNotePayload(CaptureItem item, String pin, bool isDark) {
    String decryptedContent = '';
    try {
      decryptedContent = CryptoEngine.xorProcess(item.content, pin);
    } catch (e) {
      decryptedContent = 'DECRYPTION FAULT';
    }

    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final formattedDate = _formatCustomDate(item.timestamp);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.85),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: dialogBg,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lock_open, color: textMain, size: 13),
                          const SizedBox(width: 8),
                          Text(
                            item.title.isNotEmpty ? item.title.toUpperCase() : 'UNLOCKED CRYPTO BLOCK',
                            style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                          ),
                        ],
                      ),
                      Text(
                        formattedDate,
                        style: TextStyle(color: isDark ? const Color(0xFF666666) : const Color(0xFF888888), fontSize: 9, fontFamily: 'Courier'),
                      ),
                    ],
                  ),
                  const Divider(height: 24, thickness: 0.8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        decryptedContent,
                        style: TextStyle(color: textMain, fontSize: 13, height: 1.5, letterSpacing: 0.02),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          final unpackedItem = CaptureItem(
                            id: item.id,
                            title: item.title,
                            content: decryptedContent,
                            type: item.type,
                            timestamp: item.timestamp,
                          );
                          _navigateToEdit(context, unpackedItem);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: borderColor, width: 0.8),
                          ),
                          child: Text('EDIT TEXT', style: TextStyle(color: textMain, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(color: textMain),
                          child: Text('CLOSE RUNTIME', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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

  void _navigateToEdit(BuildContext context, CaptureItem item) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => EditNoteScreen(item: item),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'note' || e.type == 'encrypted_note').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    final ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: const Color(0xFF5F0E0D).withOpacity(0.6),
          selectionHandleColor: const Color(0xFF5F0E0D),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('QUICK NOTES', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)),
            const SizedBox(height: 16),

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
                contentPadding: const EdgeInsets.only(bottom: 8),
              ),
            ),
            Container(height: 1.0, color: const Color(0xFFa6a6a6)),
            const SizedBox(height: 8),
            TextField(
              controller: _bodyController,
              style: TextStyle(color: textMain, fontSize: 13),
              maxLines: 4,
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

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    final String? globalPin = Hive.box('rocen_settings_box').get('system_crypto_pin');
                    if (globalPin == null || globalPin.isEmpty) {
                      _showMissingKeyDialog(isDark);
                    } else {
                      setState(() => _isNoteLocked = !_isNoteLocked);
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Icon(
                        _isNoteLocked ? Icons.lock : Icons.lock_open,
                        size: 14,
                        color: _isNoteLocked ? textMain : textSub,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isNoteLocked ? 'ENCRYPTED LOG PIPELINE ACTIVE' : 'STANDARD TEXT DEPLOYMENT',
                        style: TextStyle(
                          color: _isNoteLocked ? textMain : textSub,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.02,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _compileAndSaveNote,
                  child: Text('COMMIT', style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),

            Divider(color: ruleBorder, height: 16, thickness: 0.8),

            Expanded(
              child: items.isEmpty
                  ? Center(
                child: Text(
                  'NO ACTIVE NOTE REGISTRIES CURRENTLY SAVED',
                  style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05),
                ),
              )
                  : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final bool isEncrypted = item.type == 'encrypted_note';
                  final formattedDate = _formatCustomDate(item.timestamp);

                  return GestureDetector(
                    onTap: () {
                      if (isEncrypted) {
                        _promptForPinChallenge(item, isDark);
                      } else {
                        _navigateToEdit(context, item);
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
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
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: isEncrypted
                                              ? Padding(
                                            padding: const EdgeInsets.only(right: 6.0),
                                            child: Icon(Icons.lock, size: 11, color: textMain),
                                          )
                                              : const SizedBox.shrink(),
                                        ),
                                        TextSpan(
                                          text: item.title.isNotEmpty ? '${item.title.toUpperCase()}  ' : 'UNTITLED  ',
                                          style: TextStyle(
                                            color: textMain,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.02,
                                          ),
                                        ),
                                        TextSpan(
                                          text: formattedDate,
                                          style: TextStyle(
                                            color: textSub,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                isEncrypted
                                    ? Text(
                                  '● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ●',
                                  style: TextStyle(color: isDark ? const Color(0xFF333333) : const Color(0xFFCCCCCC), fontSize: 10, letterSpacing: 1.2),
                                )
                                    : AnimatedClampedText(
                                  text: item.content,
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF404040),
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
                                onTap: () {
                                  if (isEncrypted) {
                                    _promptForPinChallenge(item, isDark, openForEditing: true);
                                  } else {
                                    _navigateToEdit(context, item);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(Icons.edit_outlined, color: textSub, size: 18),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _showDeleteConfirmation(context, item.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(Icons.delete_outline_rounded, color: textSub, size: 20),
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
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _bodyController = TextEditingController(text: widget.item.content);
    _isNoteLocked = widget.item.type == 'encrypted_note';

    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.removeListener(_onTextChanged);
    _bodyController.removeListener(_onTextChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _dynamicSave();
    });
  }

  void _dynamicSave() {
    final bool originalIsLocked = widget.item.type == 'encrypted_note';
    if (_isNoteLocked != originalIsLocked) return;

    String contentToPersist = _bodyController.text.trim();

    if (_isNoteLocked) {
      final String? pin = Hive.box('rocen_settings_box').get('system_crypto_pin');
      if (pin != null && pin.isNotEmpty) {
        contentToPersist = CryptoEngine.xorProcess(contentToPersist, pin);
      }
    }

    ref.read(localDatabaseProvider.notifier).updateItem(
      widget.item.id,
      contentToPersist,
      title: _titleController.text.trim(),
    );
  }

  void _toggleLock() {
    final String? globalPin = Hive.box('rocen_settings_box').get('system_crypto_pin');
    final isDark = ref.read(themeProvider);

    if (globalPin == null || globalPin.isEmpty) {
      _showMissingKeyDialog(isDark);
    } else {
      setState(() {
        _isNoteLocked = !_isNoteLocked;
      });
      _dynamicSave();
    }
  }

  void _showMissingKeyDialog(bool isDark) {
    final textMain = isDark ? Colors.white : Colors.black;
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    final dialogBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.7),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dialogBg,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SECURITY LOCK OUTCAST',
                    style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SET KEY FIRST FROM SETTING TO USE THIS FEATURE',
                    style: TextStyle(color: textMain, fontSize: 12, height: 1.5, letterSpacing: 0.02, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: borderColor, width: 0.8),
                        ),
                        child: Text('ACKNOWLEDGE', style: TextStyle(color: textMain, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: const Color(0xFF5F0E0D).withOpacity(0.6),
          selectionHandleColor: const Color(0xFF5F0E0D),
        ),
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: textMain, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('EDIT NOTE', style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
          actions: [
            IconButton(
              icon: Icon(
                _isNoteLocked ? Icons.lock : Icons.lock_open,
                color: textMain,
                size: 20,
              ),
              onPressed: _toggleLock,
            ),
            TextButton(
              onPressed: () async {
                _debounceTimer?.cancel();
                String contentToPersist = _bodyController.text.trim();
                final bool originalIsLocked = widget.item.type == 'encrypted_note';

                if (_isNoteLocked) {
                  final String? pin = Hive.box('rocen_settings_box').get('system_crypto_pin');
                  if (pin != null && pin.isNotEmpty) {
                    contentToPersist = CryptoEngine.xorProcess(contentToPersist, pin);
                  }
                }

                if (_isNoteLocked == originalIsLocked) {
                  await ref.read(localDatabaseProvider.notifier).updateItem(
                    widget.item.id,
                    contentToPersist,
                    title: _titleController.text.trim(),
                  );
                } else {
                  await ref.read(localDatabaseProvider.notifier).deleteItem(widget.item.id);
                  await ref.read(localDatabaseProvider.notifier).insertItem(
                    contentToPersist,
                    _isNoteLocked ? 'encrypted_note' : 'note',
                    title: _titleController.text.trim(),
                  );
                }

                if (context.mounted) Navigator.pop(context);
              },
              child: Text('SAVE', style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600),
                  cursorColor: textMain,
                  decoration: InputDecoration(
                    hintText: 'Title',
                    hintStyle: TextStyle(color: textSub, fontWeight: FontWeight.w400),
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                  ),
                ),
                Container(height: 0.8, color: ruleBorder, margin: const EdgeInsets.symmetric(vertical: 12)),
                Expanded(
                  child: TextField(
                    controller: _bodyController,
                    style: TextStyle(color: textMain, fontSize: 14, height: 1.6),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    cursorColor: textMain,
                    decoration: InputDecoration(
                      hintText: 'Note content...',
                      hintStyle: TextStyle(color: textSub),
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