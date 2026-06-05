import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../main.dart';

class ClipboardScreen extends ConsumerWidget {
  const ClipboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);
    final items = ref.watch(localDatabaseProvider).where((e) => e.type == 'clip').toList();

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFF888888) : const Color(0xFF404040);
    final borderColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);
    final containerBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEEEEEE);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CLIPBOARD REGISTRY',
            style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              ref.read(localDatabaseProvider.notifier).insertItem('Sync from system clipboard buffer: CTR-${DateTime.now().millisecond}', 'clip');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: borderColor, width: 0.8)),
              alignment: Alignment.center,
              child: Text(
                'FETCH SYSTEM PASTE',
                style: TextStyle(color: textMain, fontSize: 11, letterSpacing: 0.05),
              ),
            ),
          ),
          Divider(color: borderColor, height: 32, thickness: 0.8),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  color: containerBg,
                  child: Text(items[index].content, style: TextStyle(color: textSub, fontSize: 12)),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}