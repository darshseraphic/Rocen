import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'navbar.dart';
import 'features/splashscreen.dart';

// Modern Notifier architecture pulling persisted values straight from disk
class ThemeNotifier extends Notifier<bool> {
  @override
  bool build() {
    return Hive.box('rocen_settings_box').get('isDark', defaultValue: true);
  }

  void toggleTheme() {
    state = !state;
    Hive.box('rocen_settings_box').put('isDark', state);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, bool>(ThemeNotifier.new);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
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
        scaffoldBackgroundColor:
        isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      ),
      home: AnimatedSplashScreen(
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Expanded(child: activeModule.screen),
                const MinimalNavbar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}