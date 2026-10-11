import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake config so tests never depend on the real (untracked) .env file.
void loadTestEnv() {
  dotenv.testLoad(fileInput: 'API_ENDPOINT=https://example.test\nAPI_KEY=test');
}

/// Stubs the native plugins the app touches so screens can render headlessly.
void mockPlatformPlugins() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) async => null);
}

/// Amplify never finishes configuring without a native platform, so the
/// "Initializing..." spinner never stops; pump fixed frames instead of settling.
Future<void> pumpFrames(WidgetTester tester) => tester.pump(const Duration(milliseconds: 500));
