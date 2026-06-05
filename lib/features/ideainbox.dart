import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../main.dart';

class IdeaInboxScreen extends ConsumerStatefulWidget {
  const IdeaInboxScreen({super.key});

  @override
  ConsumerState<IdeaInboxScreen> createState() => _IdeaInboxScreenState();
}

class _IdeaInboxScreenState extends ConsumerState<IdeaInboxScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider);
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'idea').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF666666);
    final textContent = isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1F1F1F);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CONCEPT INBOX',
            style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: TextStyle(color: textMain, fontSize: 14),
                  cursorColor: textMain,
                  decoration: InputDecoration(
                    hintText: 'Stash quick thought logic...',
                    hintStyle: TextStyle(color: textSub),
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add, color: textMain, size: 18),
                onPressed: () {
                  if (_controller.text.trim().isNotEmpty) {
                    ref.read(localDatabaseProvider.notifier).insertItem(_controller.text.trim(), 'idea');
                    _controller.clear();
                  }
                },
              )
            ],
          ),
          Divider(color: borderColor, height: 24, thickness: 0.8),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8)),
                  child: Text(items[index].content, style: TextStyle(color: textContent, fontSize: 13)),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}