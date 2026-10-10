import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/session_security_manager.dart';
import 'package:Rocen/core/session_unlock_service.dart';
import 'package:Rocen/features/lock_screen.dart';

void main() {
  setUp(() {
    SessionSecurityManager.instance.resetForTesting();
  });

  Future<void> pumpLockScreen(
    WidgetTester tester,
    Future<void> Function(String password) onUnlock,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(onUnlock: onUnlock),
      ),
    );
  }

  testWidgets('shows "no account" message for NoLocalAuthorityException cause',
      (tester) async {
    await pumpLockScreen(tester, (password) async {
      throw const SessionAuthenticationException(
        'authentication failed',
        NoLocalAuthorityException(),
      );
    });

    await tester.enterText(find.byType(TextField), 'anything');
    await tester.tap(find.text('UNLOCK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No account has been set up'), findsOneWidget);
  });

  testWidgets(
      'shows "incorrect password" message for UnlockAuthenticationFailedException cause',
      (tester) async {
    await pumpLockScreen(tester, (password) async {
      throw const SessionAuthenticationException(
        'authentication failed',
        UnlockAuthenticationFailedException(),
      );
    });

    await tester.enterText(find.byType(TextField), 'wrong-password');
    await tester.tap(find.text('UNLOCK'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect password.'), findsOneWidget);
  });

  testWidgets('shows interrupted message for SessionActivationException',
      (tester) async {
    await pumpLockScreen(tester, (password) async {
      throw const SessionActivationException('rolled back');
    });

    await tester.enterText(find.byType(TextField), 'somepassword');
    await tester.tap(find.text('UNLOCK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('interrupted'), findsOneWidget);
  });

  testWidgets('clears the password field after a failed attempt',
      (tester) async {
    await pumpLockScreen(tester, (password) async {
      throw const SessionAuthenticationException(
        'authentication failed',
        UnlockAuthenticationFailedException(),
      );
    });

    await tester.enterText(find.byType(TextField), 'wrong-password');
    await tester.tap(find.text('UNLOCK'));
    await tester.pumpAndSettle();

    final TextField field = tester.widget(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('does not call onUnlock for an empty password', (tester) async {
    int callCount = 0;
    await pumpLockScreen(tester, (password) async {
      callCount++;
    });

    await tester.tap(find.text('UNLOCK'));
    await tester.pumpAndSettle();

    expect(callCount, 0);
  });
}
