import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../main.dart';

class VoiceNoteScreen extends ConsumerStatefulWidget {
  const VoiceNoteScreen({super.key});

  @override
  ConsumerState<VoiceNoteScreen> createState() => _VoiceNoteScreenState();
}

class _VoiceNoteScreenState extends ConsumerState<VoiceNoteScreen> {
  // Simulates which audio file is currently playing
  String? _playingItemId;

  void _showRecordingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _RecordAudioSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'voice').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    final ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VOICE MEMOS', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 24),

          GestureDetector(
            onTap: () => _showRecordingSheet(context),
            child: Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(border: Border.all(color: ruleBorder, width: 0.8)),
              alignment: Alignment.center,
              child: Text(
                '[ PRESS TO CAPTURE AUDIO ]',
                style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05),
              ),
            ),
          ),

          Divider(color: ruleBorder, height: 32, thickness: 0.8),

          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isPlaying = _playingItemId == item.id;

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: ruleBorder, width: 0.8)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.content,
                        style: TextStyle(
                          color: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF404040),
                          fontSize: 13,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            // Toggle play/pause simulation
                            _playingItemId = isPlaying ? null : item.id;
                          });
                        },
                        child: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: textMain,
                          size: 16,
                        ),
                      ),
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

// Minimalist Bottom Sheet for Recording
class _RecordAudioSheet extends ConsumerStatefulWidget {
  const _RecordAudioSheet();

  @override
  ConsumerState<_RecordAudioSheet> createState() => _RecordAudioSheetState();
}

class _RecordAudioSheetState extends ConsumerState<_RecordAudioSheet> {
  bool _isRecording = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });
  }

  void _saveRecording() {
    final recordName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Audio Trace: ${DateTime.now().toIso8601String().substring(11, 19)}';

    ref.read(localDatabaseProvider.notifier).insertItem(recordName, 'voice');
    Navigator.pop(context); // Close the sheet
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF888888);
    final bgColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Padding(
      // Padding to push the sheet up when the keyboard appears
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(32.0),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: borderColor, width: 0.8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isRecording ? 'RECORDING...' : 'READY TO RECORD',
              style: TextStyle(
                color: _isRecording ? const Color(0xFFEF4444) : textSub,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 32),

            // Minimal Mic Button
            GestureDetector(
              onTap: _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording ? const Color(0xFFEF4444) : Colors.transparent,
                  border: Border.all(
                      color: _isRecording ? const Color(0xFFEF4444) : borderColor,
                      width: 0.8
                  ),
                ),
                child: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
                  color: _isRecording ? Colors.white : textMain,
                  size: 28,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Name Input
            TextField(
              controller: _nameController,
              textAlign: TextAlign.center,
              style: TextStyle(color: textMain, fontSize: 14),
              cursorColor: textMain,
              decoration: InputDecoration(
                hintText: 'Record name',
                hintStyle: TextStyle(color: textSub),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: textMain)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),

            const SizedBox(height: 24),

            // Save/Dismiss Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('CANCEL', style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: _isRecording ? null : _saveRecording,
                  child: Text(
                    'SAVE',
                    style: TextStyle(
                      color: _isRecording
                          ? textSub.withValues(alpha: 0.5)
                          : textMain,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}