import 'package:flutter_test/flutter_test.dart';
import 'package:quote_me/main.dart';
import 'helpers/platform_mocks.dart';

void main() {
  setUpAll(loadTestEnv);
  setUp(mockPlatformPlugins);

  testWidgets('QuoteMeApp boots to the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const QuoteMeApp());
    await pumpFrames(tester);

    expect(find.text('Quote Me'), findsOneWidget);
    expect(find.text('Get Quote'), findsOneWidget);
  });
}
