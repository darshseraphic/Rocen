import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/session_security_manager.dart';

/// Reproduces, in isolation, the exact pattern `_SettingsScreenState` uses
/// (`_trackSensitiveController` / `_trackSensitiveControllers` +
/// unregistering the whole list in `dispose()`), without needing to drive
/// the full `SettingsScreen` widget tree end-to-end. This verifies the
/// mechanism settings.dart relies on actually behaves as documented:
///   - a tracked controller's text is cleared by a session lock,
///   - clearing a controller that was already disposed by its own dialog's
///     normal teardown does not throw and does not break other callbacks,
///   - unregistering on State.dispose() means a lock after the widget is
///     gone does not touch (or crash on) a disposed controller.
class _FakeSettingsHost extends StatefulWidget {
  const _FakeSettingsHost();

  @override
  State<_FakeSettingsHost> createState() => _FakeSettingsHostState();
}

class _FakeSettingsHostState extends State<_FakeSettingsHost> {
  final List<void Function()> _unregisterSensitiveCleanups = [];
  final List<TextEditingController> ownedControllers = [];

  TextEditingController trackSensitiveController(
    TextEditingController controller,
  ) {
    ownedControllers.add(controller);
    _unregisterSensitiveCleanups.add(
      SessionSecurityManager.instance.registerCleanup(() {
        try {
          controller.clear();
        } catch (_) {}
      }),
    );
    return controller;
  }

  @override
  void dispose() {
    for (final unregister in _unregisterSensitiveCleanups) {
      unregister();
    }
    for (final controller in ownedControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUp(() {
    SessionSecurityManager.instance.resetForTesting();
  });

  testWidgets('a tracked controller is cleared by lockSync', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state = tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));

    final controller = state.trackSensitiveController(
      TextEditingController(text: 'super-secret-password'),
    );
    expect(controller.text, 'super-secret-password');

    SessionSecurityManager.instance.lockSync();

    expect(controller.text, isEmpty);
  });

  testWidgets(
      'clearing an already-disposed tracked controller does not throw and '
      'does not block other cleanup callbacks', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state = tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));

    final earlyController = TextEditingController(text: 'early-dialog-password');
    state.trackSensitiveController(earlyController);
    // Simulate the dialog's own normal teardown disposing its controller
    // before any lock happens - several dialogs in settings.dart do (or, in
    // a couple of cases, should but currently do not) dispose their own
    // controller independently of the session cleanup registry.
    earlyController.dispose();

    bool laterCleanupRan = false;
    SessionSecurityManager.instance.registerCleanup(() {
      laterCleanupRan = true;
    });

    expect(() => SessionSecurityManager.instance.lockSync(), returnsNormally);
    expect(laterCleanupRan, isTrue);
  });

  testWidgets(
      'unregistering on State.dispose() means a later lock does not touch '
      'a disposed controller', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state = tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));
    state.trackSensitiveController(TextEditingController());

    // Remove the widget from the tree, triggering its dispose(), which
    // unregisters the cleanup AND disposes the controller (mirroring
    // _SettingsScreenState.dispose()).
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    // A lock after the widget is gone must not throw, even though the
    // controller it used to track is now disposed and no longer
    // registered. (We do not additionally assert on what happens if
    // something tries to read the disposed controller's `.text` afterward -
    // that is a general Flutter TextEditingController lifecycle contract
    // unrelated to this cleanup mechanism, not something this test needs to
    // pin down.)
    expect(() => SessionSecurityManager.instance.lockSync(), returnsNormally);
  });

  testWidgets('multiple tracked controllers are all cleared independently',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state = tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));

    final passwordController =
        state.trackSensitiveController(TextEditingController(text: 'pw'));
    final mnemonicControllers = List.generate(
      12,
      (i) => state.trackSensitiveController(TextEditingController(text: 'word$i')),
    );

    SessionSecurityManager.instance.lockSync();

    expect(passwordController.text, isEmpty);
    for (final c in mnemonicControllers) {
      expect(c.text, isEmpty);
    }
  });
}
