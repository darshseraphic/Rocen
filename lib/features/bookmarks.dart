import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'bookmark').toList();
    final controller = TextEditingController();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('URL INDEX', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'https://',
              hintStyle: TextStyle(color: Color(0xFF737373)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1F1F1F))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  ref.read(localDatabaseProvider.notifier).insertItem(controller.text.trim(), 'bookmark');
                  controller.clear();
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
                  title: Text(items[index].content, style: const TextStyle(color: Color(0xFF737373), fontSize: 13, decoration: TextDecoration.underline)),
                  trailing: const Icon(Icons.open_in_new, color: Color(0xFF1F1F1F), size: 12),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}