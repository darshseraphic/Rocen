import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // REQUIRED IMPORT FOR TERMINAL SYSTEM CONTROLS
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'navbar.dart';
import 'features/splashscreen.dart';

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

  // FORCE HARDWARE WINDOW MANAGER TO PIN INTERFACE STRICLY TO VERTICAL AXIS
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // HIDE BOTTOM NAVIGATION BAR (KEPT TOP STATUS BAR)
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );

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

    final backgroundColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
      ),
      child: MaterialApp(
        title: 'Rocen',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: isDark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: backgroundColor,
        ),
        home: AnimatedSplashScreen(
          child: Scaffold(
            resizeToAvoidBottomInset: true,
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
      ),
    );
  }
}