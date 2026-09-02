import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Rocen/main.dart';

void main() {
  testWidgets('Capture OS boot smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: RocenApp(),
      ),
    );
    expect(find.text('QUICK NOTES'), findsOneWidget);
  });
}
