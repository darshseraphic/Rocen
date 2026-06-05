import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../main.dart';

class BookmarksScreen extends ConsumerStatefulWidget {
  const BookmarksScreen({super.key});

  @override
  ConsumerState<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends ConsumerState<BookmarksScreen> {
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
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'bookmark').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF737373) : const Color(0xFF666666);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'URL INDEX',
            style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            style: TextStyle(color: textMain, fontSize: 14),
            cursorColor: textMain,
            decoration: InputDecoration(
              hintText: 'https://',
              hintStyle: TextStyle(color: textSub),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: textMain)),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(Icons.arrow_forward, color: textMain, size: 16),
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  ref.read(localDatabaseProvider.notifier).insertItem(_controller.text.trim(), 'bookmark');
                  _controller.clear();
                }
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    items[index].content,
                    style: TextStyle(color: textSub, fontSize: 13, decoration: TextDecoration.underline),
                  ),
                  trailing: Icon(Icons.open_in_new, color: borderColor, size: 12),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}