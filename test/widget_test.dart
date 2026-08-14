import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wbai_radio/main.dart';
import 'package:wbai_radio/core/di/service_locator.dart';

void main() {

  testWidgets('WBAI Radio App smoke test', (WidgetTester tester) async {
    // Set up inside the test body, not setUpAll: this test is skipped, and
    // setUpAll runs even for skipped tests. Spinning up audio_service and
    // AudioSession platform channels for a test that never runs was a
    // source of intermittent suite failures under parallel load.
    // setupServiceLocator() loads the saved theme via SharedPreferences, which
    // has no platform channel in a headless test.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await setupServiceLocator();

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
