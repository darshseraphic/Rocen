import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rocen/main.dart';

void main() {
  testWidgets('Capture OS boot smoke test', (WidgetTester tester) async {
    // Build our app under a ProviderScope and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: CaptureApp(),
      ),
    );

    // Verify that the application boots directly into the default module header
    expect(find.text('QUICK NOTES'), findsOneWidget);
  });
}