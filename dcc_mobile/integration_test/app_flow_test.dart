import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quote_me/main.dart' as app;

/// Run on a device or desktop (hits the live public API):
///   flutter test integration_test -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps until [finder] matches; spinners mean pumpAndSettle may never return.
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>();
        fail('Timed out waiting for $finder; visible text: ${texts.join(' | ')}');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Lets route transitions finish (pumpAndSettle can hang on live spinners).
  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    for (var t = Duration.zero; t < duration; t += const Duration(milliseconds: 100)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openMenuItem(WidgetTester tester, String label) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    final item = find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text(label));
    await pumpUntilFound(tester, item);
    await pumpFor(tester, const Duration(seconds: 1)); // let the menu finish animating in
    await tester.tap(item);
  }

  testWidgets('Quote Me end-to-end flow', (WidgetTester tester) async {
    await app.main();
    await pumpUntilFound(tester, find.text('Get Quote'));
    expect(find.text('Quote Me'), findsOneWidget);

    // Fetch a live quote: once loaded the share button appears
    await tester.tap(find.text('Get Quote'));
    await pumpUntilFound(tester, find.byTooltip('Share Quote'));
    expect(find.text('Get Quote'), findsOneWidget);

    // Settings opens and returns home
    await openMenuItem(tester, 'Settings');
    await pumpUntilFound(tester, find.text('Theme Mode'));
    await tester.pageBack();
    await pumpUntilFound(tester, find.text('Get Quote'));
    await pumpFor(tester, const Duration(seconds: 1));

    // Sign-in screen opens and returns home without logging in
    await openMenuItem(tester, 'Sign In / Sign Up');
    await pumpUntilFound(tester, find.text('Email Address'));
    expect(find.text('Password'), findsOneWidget);
    final backToQuotes = find.text('Back to Quotes');
    await tester.ensureVisible(backToQuotes);
    await tester.tap(backToQuotes);
    await pumpUntilFound(tester, find.text('Get Quote'));
    await pumpFor(tester, const Duration(seconds: 1));
  });
}
