import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:wbai_radio/main.dart';
import 'package:wbai_radio/core/di/service_locator.dart';

void main() {
  setUpAll(() async {
    // Initialize ServiceRegistry (new pattern)
    await setupServiceLocator();
  });

  tearDownAll(() {
    // Clean up is handled automatically by ServiceRegistry
  });

  testWidgets('WBAI Radio App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WBAIRadioApp());

    // The play button (filled play circle) is shown on first launch.
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
  },
      // Skipped: building the full app initializes audio_service / AudioSession,
      // which require platform channels not available in a headless test. This
      // needs an integration test on a device/emulator, or platform-channel
      // mocks. Logic-level behavior is covered by the unit tests in this dir.
      skip: true);
}
