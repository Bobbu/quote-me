import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quote_me/screens/quote_screen.dart';
import '../helpers/platform_mocks.dart';

Future<void> pumpQuoteScreen(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: QuoteScreen()));
  await pumpFrames(tester);
}

void main() {
  setUpAll(loadTestEnv);

  setUp(mockPlatformPlugins);

  group('QuoteScreen Widget Tests', () {
    testWidgets('shows title, empty state and Get Quote button', (tester) async {
      await pumpQuoteScreen(tester);

      expect(find.text('Quote Me'), findsOneWidget);
      expect(find.text('Ready for inspiration?'), findsOneWidget);
      expect(find.text('Get Quote'), findsOneWidget);
    });

    testWidgets('Get Quote button is enabled', (tester) async {
      await pumpQuoteScreen(tester);

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Get Quote'), matching: find.bySubtype<ButtonStyleButton>()),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('share button is hidden until a quote is shown', (tester) async {
      await pumpQuoteScreen(tester);

      expect(find.byTooltip('Share Quote'), findsNothing);
    });

    testWidgets('menu offers About and Settings to everyone', (tester) async {
      await pumpQuoteScreen(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await pumpFrames(tester);

      expect(find.text('About'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders on small and large screens without overflow', (tester) async {
      for (final size in const [Size(320, 640), Size(1024, 1366)]) {
        await tester.binding.setSurfaceSize(size);
        await pumpQuoteScreen(tester);
        expect(find.text('Quote Me'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
    });
  });
}
