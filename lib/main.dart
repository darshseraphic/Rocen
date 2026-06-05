import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'navbar.dart'; // Exposes both MinimalNavbar and navigationProvider

final themeProvider = StateProvider<bool>((ref) => true); // true = Dark, false = Light

void main() {
  runApp(
    const ProviderScope(
      child: CaptureApp(),
    ),
  );
}

class CaptureApp extends ConsumerWidget {
  const CaptureApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);

    return ThemeData(
      scaffoldBackgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
      useMaterial3: true,
    ).let((themeData) => MaterialApp(
      title: 'ROCNE CAPTURE',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      home: const MainNavigationShell(),
    ));
  }
}

class MainNavigationShell extends ConsumerWidget {
  const MainNavigationShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentView = ref.watch(navigationProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: currentView.screen,
              ),
            ),
            const MinimalNavbar(),
          ],
        ),
      ),
    );
  }
}

// Quick helper extension method to clean up theme generation
extension LetExtension<T> on T {
  R let<R>(R Function(T) block) => block(this);
}