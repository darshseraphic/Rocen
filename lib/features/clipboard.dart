import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';

class ClipboardScreen extends ConsumerWidget {
  const ClipboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'clip').toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CLIPBOARD REGISTRY', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              ref.read(localDatabaseProvider.notifier).insertItem('Sync from system clipboard buffer: CTR-${DateTime.now().millisecond}', 'clip');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFF1F1F1F), width: 0.8)),
              alignment: Alignment.center,
              child: const Text(
                'FETCH SYSTEM PASTE',
                style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 0.05),
              ),
            ),
          ),
          const Divider(color: Color(0xFF1F1F1F), height: 32, thickness: 0.8),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  color: const Color(0xFF0F0F0F),
                  child: Text(items[index].content, style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}