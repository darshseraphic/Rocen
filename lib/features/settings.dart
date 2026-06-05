import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);

    final textMain = isDark ? Colors.white : Colors.black;
    final textSub = isDark ? const Color(0xFFA3A3A3) : const Color(0xFF525252);
    final ruleBorder = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E5E5);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'SYSTEM SETTINGS',
              style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.02)
          ),
          const SizedBox(height: 32),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DARK ARCHITECTURE', style: TextStyle(color: textSub, fontSize: 11, letterSpacing: 0.05)),
              GestureDetector(
                onTap: () => ref.read(themeProvider.notifier).state = !isDark,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: 36,
                  height: 20,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(color: isDark ? Colors.white : const Color(0xFF737373), width: 0.8),
                    color: isDark ? Colors.black : const Color(0xFFE5E5E5),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 14,
                      height: 14,
                      color: isDark ? Colors.white : const Color(0xFF171717),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Divider(color: ruleBorder, height: 1, thickness: 0.8),
        ],
      ),
    );
  }
}