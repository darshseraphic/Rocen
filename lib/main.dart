import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'navbar.dart';

// Modern Notifier architecture compatible with your current package dependencies
class ThemeNotifier extends Notifier<bool> {
  @override
  bool build() {
    return true; // Default state: dark mode active
  }

  void toggleTheme() {
    state = !state;
  }
}

// Clean initialization using modern NotifierProvider syntax
final themeProvider = NotifierProvider<ThemeNotifier, bool>(ThemeNotifier.new);

void main() async {
  // Ensure framework low-level binding services are attached prior to initializing storage
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive key-value local storage backend engine
  await Hive.initFlutter();

  runApp(
    const ProviderScope(
      child: RocenApp(),
    ),
  );
}

class RocenApp extends ConsumerWidget {
  const RocenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);
    final activeModule = ref.watch(navigationProvider);

    return MaterialApp(
      title: 'Rocen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Dynamic Content Frame Module Viewer switching screens based on Navbar selections
              Expanded(
                child: activeModule.screen,
              ),
              // Persistent Baseline System Minimal Navbar Fixed Framework Row
              const MinimalNavbar(),
            ],
          ),
        ),
      ),
    );
  }
}