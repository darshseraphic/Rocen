import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocen/core/sensitive_controller_cleanup.dart';
import 'package:rocen/core/session_security_manager.dart';

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
  // The REAL production helper that _SettingsScreenState uses.
  final SensitiveControllerCleanup cleanup = SensitiveControllerCleanup();
  final List<TextEditingController> ownedControllers = [];

  TextEditingController trackSensitiveController(
    TextEditingController controller,
  ) {
    ownedControllers.add(controller);
    return cleanup.track(controller);
  }

  @override
  void dispose() {
    cleanup.disposeAll();
    for (final controller in ownedControllers) {
      try {
        controller.dispose();
      } catch (_) {}
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
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));

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
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));

    final earlyController =
        TextEditingController(text: 'early-dialog-password');
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
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));
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
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));

    final passwordController =
        state.trackSensitiveController(TextEditingController(text: 'pw'));
    final mnemonicControllers = List.generate(
      12,
      (i) =>
          state.trackSensitiveController(TextEditingController(text: 'word$i')),
    );

    SessionSecurityManager.instance.lockSync();

    expect(passwordController.text, isEmpty);
    for (final c in mnemonicControllers) {
      expect(c.text, isEmpty);
    }
  });

  testWidgets(
      'a STILL-MOUNTED controller is cleared on EVERY lock, not just the '
      'first (the registry is one-shot; the cleanup re-arms)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));
    final controller = state
        .trackSensitiveController(TextEditingController(text: 'first-secret'));

    SessionSecurityManager.instance.lockSync();
    expect(controller.text, isEmpty, reason: 'first lock');

    // Same mounted controller receives NEW sensitive text.
    controller.text = 'second-secret';
    expect(controller.text, 'second-secret');
    SessionSecurityManager.instance.lockSync();
    expect(controller.text, isEmpty, reason: 'second lock');

    controller.text = 'third-secret';
    SessionSecurityManager.instance.lockSync(); // lifecycle-style repeat
    expect(controller.text, isEmpty, reason: 'third lock');
    expect(state.cleanup.trackedCount, 1);
  });

  testWidgets(
      'a controller disposed by its own dialog is dropped after the first '
      'lock and never re-armed; live controllers keep being cleared',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));
    final live =
        state.trackSensitiveController(TextEditingController(text: 'live'));
    final dialogOwned = TextEditingController(text: 'dialog');
    state.cleanup.track(dialogOwned); // not in ownedControllers: dialog's own
    dialogOwned.dispose();

    expect(() => SessionSecurityManager.instance.lockSync(), returnsNormally);
    expect(live.text, isEmpty);
    expect(state.cleanup.trackedCount, 1,
        reason: 'the disposed controller was dropped');

    live.text = 'again';
    expect(() => SessionSecurityManager.instance.lockSync(), returnsNormally);
    expect(live.text, isEmpty);
  });

  testWidgets(
      'after the owner is disposed no re-armed cleanup survives, and an '
      'unrelated one-shot callback still runs exactly once per lock',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));
    final controller =
        state.trackSensitiveController(TextEditingController(text: 'secret'));
    SessionSecurityManager.instance.lockSync(); // consumes + re-arms
    expect(controller.text, isEmpty);

    final SensitiveControllerCleanup cleanup = state.cleanup;
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(cleanup.trackedCount, 0);

    int unrelated = 0;
    SessionSecurityManager.instance.registerCleanup(() => unrelated++);
    expect(() => SessionSecurityManager.instance.lockSync(), returnsNormally);
    expect(unrelated, 1);
    SessionSecurityManager.instance.lockSync();
    expect(unrelated, 1, reason: 'one-shot: not re-invoked on later locks');
  });

  testWidgets('release clears and unregisters only the selected controller',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));
    final first =
        state.trackSensitiveController(TextEditingController(text: 'first'));
    final second =
        state.trackSensitiveController(TextEditingController(text: 'second'));
    state.cleanup.release(first);
    expect(first.text, isEmpty);
    expect(second.text, 'second');

    first.text = 'released-after-close';
    second.text = 'still-live-secret';
    SessionSecurityManager.instance.lockSync();
    expect(first.text, 'released-after-close',
        reason: 'released callback no longer runs');
    expect(second.text, isEmpty,
        reason: 'the other controller still receives lock cleanup');
  });

  testWidgets(
      'disposeAll clears live controller contents before releasing '
      'callbacks', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeSettingsHost()));
    final state =
        tester.state<_FakeSettingsHostState>(find.byType(_FakeSettingsHost));
    final controller = state.trackSensitiveController(
      TextEditingController(text: 'clear-before-owner-dispose'),
    );
    state.cleanup.disposeAll();
    expect(controller.text, isEmpty);
    controller.text = 'owner-still-holds-it';
    SessionSecurityManager.instance.lockSync();
    expect(controller.text, 'owner-still-holds-it');
  });
}
