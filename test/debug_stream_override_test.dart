import 'package:flutter_test/flutter_test.dart';
import 'package:wbai_radio/core/constants/stream_constants.dart';
import 'package:wbai_radio/core/testing/debug_stream_override.dart';

/// The debug outage presets redirect the app at a dead endpoint so failures can
/// be rehearsed without taking the station off air. The safety property that
/// matters: they must never be able to point a real listener's app away from
/// the live stream.
void main() {
  tearDown(DebugStreamOverride.clear);

  test('defaults to the real stream', () {
    expect(DebugStreamOverride.isOverridden, isFalse);
    expect(DebugStreamOverride.effectiveUrl, StreamConstants.streamUrl);
  });

  test('clear() always returns to the live stream', () {
    DebugStreamOverride.apply(DebugOutagePreset.refused);
    DebugStreamOverride.clear();
    expect(DebugStreamOverride.effectiveUrl, StreamConstants.streamUrl);
    expect(DebugStreamOverride.activeLabel, isNull);
  });

  test('the "live" preset carries no URL, so selecting it restores the stream',
      () {
    expect(DebugOutagePreset.live.url, isNull);
  });

  test('every failing preset points somewhere unreachable, never at the station',
      () {
    final failing =
        DebugOutagePreset.all.where((p) => p.url != null).toList();
    expect(failing, isNotEmpty);
    for (final preset in failing) {
      expect(preset.url, isNot(StreamConstants.streamUrl),
          reason: '${preset.label} must not resolve to the live stream');
      expect(preset.expected, isNotEmpty,
          reason: '${preset.label} needs a stated expected outcome so a run '
              'can be judged pass or fail');
    }
  });

  test('presets are distinct', () {
    final urls = DebugOutagePreset.all.map((p) => p.url).toList();
    expect(urls.toSet().length, urls.length);
  });

  // In a release build kDebugMode is false, so apply() is a no-op and url is
  // always null — verified for real by grepping the release binary in
  // docs/TESTING_outage_scenarios.md. Under `flutter test` kDebugMode is true,
  // so here we can only assert the debug-side behaviour works.
  test('apply() takes effect in debug builds', () {
    DebugStreamOverride.apply(DebugOutagePreset.refused);
    expect(DebugStreamOverride.isOverridden, isTrue);
    expect(DebugStreamOverride.effectiveUrl, DebugOutagePreset.refused.url);
    expect(DebugStreamOverride.activeLabel, DebugOutagePreset.refused.label);
  });
}
