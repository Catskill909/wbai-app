import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// REGRESSION GUARD — Info.plist keys that App Store Connect requires.
///
/// ## Why this test exists
///
/// `NSMicrophoneUsageDescription` has been removed and re-added repeatedly,
/// causing rejected uploads each time it was missing (ITMS-90683, most recently
/// on build 1.0.2+13).
///
/// The trap: **this app has no microphone feature**, so the key looks like dead
/// weight and someone deletes it. But Apple's static scanner does not check
/// whether *your* code calls the API — it scans every linked binary, including
/// embedded frameworks. Two plugins reference microphone APIs:
///
///   - `audio_session`            (AVAudioSession category/record APIs)
///   - `flutter_inappwebview_ios` (WebView getUserMedia support)
///
/// So the purpose string is **mandatory for as long as those plugins ship**,
/// regardless of what the app does. Verifying by grepping the main `Runner`
/// binary is NOT sufficient — the references live in `Runner.app/Frameworks/`.
///
/// The opposite failure is also real: a dismissive string such as
/// "This app does not use the microphone" invites an App Review 5.1.1 question
/// about why microphone access is declared at all. The string must therefore
/// exist AND explain the situation honestly.
///
/// If a future release genuinely drops both plugins, verify with:
///   for f in build/ios/iphoneos/Runner.app/Frameworks/*.framework; do ... done
/// and only then consider removing the key.
void main() {
  late String plist;

  setUpAll(() {
    final file = File('ios/Runner/Info.plist');
    expect(file.existsSync(), isTrue, reason: 'ios/Runner/Info.plist not found');
    plist = file.readAsStringSync();
  });

  group('Info.plist required keys', () {
    test('NSMicrophoneUsageDescription is present', () {
      expect(plist, contains('<key>NSMicrophoneUsageDescription</key>'),
          reason: 'REQUIRED. audio_session and flutter_inappwebview_ios '
              'reference microphone APIs, so App Store Connect rejects the '
              'upload with ITMS-90683 without this key — even though the app '
              'has no microphone feature. Do not remove it.');
    });

    test('microphone purpose string is explanatory, not dismissive', () {
      final match = RegExp(
        r'<key>NSMicrophoneUsageDescription</key>\s*<string>(.*?)</string>',
        dotAll: true,
      ).firstMatch(plist);
      expect(match, isNotNull, reason: 'purpose string missing or malformed');
      final value = match!.group(1)!.trim();

      expect(value.length, greaterThan(40),
          reason: 'A terse string like "This app does not use the microphone" '
              'satisfies the scanner but invites an App Review 5.1.1 question. '
              'Explain why the permission can be requested at all.');
      expect(value.toLowerCase(), isNot(equals('this app does not use the microphone')),
          reason: 'This exact string has drawn reviewer questions before.');
    });

    test('ITSAppUsesNonExemptEncryption is declared', () {
      expect(plist, contains('<key>ITSAppUsesNonExemptEncryption</key>'),
          reason: 'Without it, App Store Connect prompts the export-compliance '
              'question on every upload.');
    });

    test('audio background mode is present exactly once', () {
      final count = '<key>UIBackgroundModes</key>'.allMatches(plist).length;
      expect(count, 1,
          reason: 'UIBackgroundModes must be declared exactly once. WBAI '
              'shipped it twice; plutil -lint accepts duplicates but only one '
              'survives parsing, and background audio depends on it.');
      expect(plist, contains('<string>audio</string>'),
          reason: 'Background audio playback requires the audio mode.');
    });
  });
}
