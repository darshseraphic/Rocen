import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'navbar.dart';

// Modern Notifier architecture pulling persisted values straight from disk
class ThemeNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Instantly loads saved user selection on startup (defaults to true/dark)
    return Hive.box('rocen_settings_box').get('isDark', defaultValue: true);
  }

  void toggleTheme() {
    state = !state;
    // Writes state changes to disk securely
    Hive.box('rocen_settings_box').put('isDark', state);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, bool>(ThemeNotifier.new);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive engine subsystems
  await Hive.initFlutter();

  // Open settings box beforehand to prevent synchronous reading race conditions
  await Hive.openBox('rocen_settings_box');

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
              Expanded(
                child: activeModule.screen,
              ),
              const MinimalNavbar(),
            ],
          ),
        ),
      ),
    );
  }
}