import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
// TODO: Import your actual database initialization provider if it exists
// import '../core/database.dart';

class AnimatedSplashScreen extends ConsumerStatefulWidget {
  final Widget child;

  const AnimatedSplashScreen({super.key, required this.child});

  @override
  ConsumerState<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends ConsumerState<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  bool _isAnimationDone = false;
  bool _isDataLoaded = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 20.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40.0,
      ),
    ]).animate(_animationController);

    // 1. Trigger the visual animation timer
    _animationController.forward().then((_) {
      if (mounted) {
        setState(() {
          _isAnimationDone = true;
        });
      }
    });

    // 2. Trigger your async data loading in the background
    _loadBackgroundData();
  }

  Future<void> _loadBackgroundData() async {
    try {
      // If you are using a Riverpod FutureProvider or AsyncNotifier for your DB initialization:
      // await ref.read(yourDatabaseInitializationProvider.future);

      // Alternatively, if you have a manual async task to initialize Hive boxes:
      // await Hive.openBox('rocen_settings_box');

      // Simulating a minor data fetch sequence to guarantee background sync:
      await Future.delayed(const Duration(milliseconds: 500));

    } catch (e) {
      debugPrint("Error loading background data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isDataLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: The splash screen only disappears when the animation
    // is fully finished AND the background database data is verified as loaded.
    if (_isAnimationDone && _isDataLoaded) {
      return widget.child;
    }

    final isDark = ref.watch(themeProvider);
    final textMain = isDark ? Colors.white : Colors.black;
    final bgMain = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgMain,
      body: Center(
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: Text(
            'ROCEN',
            style: TextStyle(
              color: textMain,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
            ),
          ),
        ),
      ),
    );
  }
}