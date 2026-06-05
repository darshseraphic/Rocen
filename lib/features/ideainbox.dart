import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';

class IdeaInboxScreen extends ConsumerWidget {
  const IdeaInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'idea').toList();
    final controller = TextEditingController();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CONCEPT INBOX', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Stash quick thought logic...',
                    hintStyle: TextStyle(color: Color(0xFF737373)),
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white, size: 18),
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    ref.read(localDatabaseProvider.notifier).insertItem(controller.text.trim(), 'idea');
                    controller.clear();
                  }
                },
              )
            ],
          ),
          const Divider(color: Color(0xFF1F1F1F), height: 24, thickness: 0.8),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFF1F1F1F), width: 0.8)),
                  child: Text(items[index].content, style: const TextStyle(color: Color(0xFFE5E5E5), fontSize: 13)),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}