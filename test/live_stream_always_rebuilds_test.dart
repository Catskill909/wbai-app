import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// REGRESSION GUARD — protects the app's core mandate:
///
///   The play button ALWAYS plays the LIVE stream and NEVER the cache.
///
/// This bug has been introduced, fixed, and reintroduced before (see
/// docs/audio-play-bug.md). Each time, it came back the same way: someone
/// chasing the ~2.6s iOS lock-screen Now Playing flash added a "resume in
/// place" fast path that skips rebuilding the AudioSource. The correct fix for
/// that flash is the native `reassertNowPlaying` pre-claim, which this app now
/// has — device-proven sufficient on KPFK with the rebuild unconditional. That fast path
/// replays whatever AVPlayer still holds in its buffer — audio from minutes
/// ago — and then stops dead when the buffer drains against a dead socket.
///
/// These tests read the handler source directly rather than driving a player,
/// because the invariant being protected is structural: there must be NO
/// conditional path through play() that skips the rebuild. A behavioral test
/// against a mock player would pass just as happily with a resume branch that
/// the mock never happens to trigger.
void main() {
  late String handlerSource;
  late String playBody;

  /// Strip `//` comments. The fix is deliberately documented in a long comment
  /// inside play() that names the old `sourceAlive` / resume-in-place shape so
  /// the next reader knows why it must not come back — these assertions must
  /// inspect CODE, not that prose.
  String stripComments(String src) => src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  setUpAll(() {
    final file = File('lib/services/audio_service/wbai_audio_handler.dart');
    expect(file.existsSync(), isTrue,
        reason: 'audio handler not found - did the file move?');
    handlerSource = file.readAsStringSync();

    // Isolate the body of play() so assertions don't accidentally match
    // _reconnect() / resetToColdStart(), which legitimately rebuild too.
    final start = handlerSource.indexOf('Future<void> play() async {');
    expect(start, greaterThan(-1), reason: 'play() not found in handler');
    final end = handlerSource.indexOf('Future<void> pause() async {', start);
    expect(end, greaterThan(start), reason: 'pause() not found after play()');
    playBody = stripComments(handlerSource.substring(start, end));
  });

  group('play() always rebuilds from the live edge', () {
    test('play() sets a fresh AudioSource', () {
      expect(playBody, contains('setAudioSource'),
          reason: 'play() must rebuild the source so it starts at the live '
              'edge. If this fails, play() can serve buffered (stale) audio.');
    });

    test('play() has no resume-in-place fast path', () {
      // The exact shape of the bug from commit bd82526.
      expect(playBody, isNot(contains('sourceAlive')),
          reason: 'sourceAlive tests whether an AVPlayerItem OBJECT exists, '
              'not whether the socket is alive. It cannot gate a resume. '
              'See docs/audio-play-bug.md.');
      expect(playBody.toLowerCase(), isNot(contains('resume-in-place')));
      expect(playBody.toLowerCase(), isNot(contains('resumeinplace')));
    });

    test('play() does not branch on platform to decide whether to rebuild', () {
      // Platform.isIOS is legitimately used in play() for the native
      // reassertNowPlaying pre-claim; what must never return is a platform
      // branch that decides whether the source gets rebuilt.
      final rebuildIdx = playBody.indexOf('setAudioSource');
      final guarded = RegExp(r'if\s*\(\s*Platform\.is\w+\s*&&')
          .allMatches(playBody)
          .any((m) => m.start < rebuildIdx);
      expect(guarded, isFalse,
          reason: 'A platform-gated condition precedes the rebuild. The '
              'rebuild must be unconditional on every platform.');
    });

    test('play() does not gate the rebuild on elapsed time since pause', () {
      // Elapsed time is not a liveness signal: a 5-second-old pause can have a
      // dead socket just as easily as a 5-minute-old one. Any staleness window
      // is a window in which the cache plays.
      expect(playBody, isNot(contains('_pausedAt')));
      expect(playBody.toLowerCase(), isNot(contains('staleness')));
      expect(playBody, isNot(contains('DateTime.now().difference')));
    });
  });

  group('a dead live stream is never silently accepted', () {
    test('completed is treated as a failure in the handler, not just logged',
        () {
      final idx = handlerSource.indexOf('case ProcessingState.completed:');
      expect(idx, greaterThan(-1));
      final branch = stripComments(handlerSource.substring(idx, idx + 2200));
      expect(branch, contains('_reconnect()'),
          reason: 'A 24/7 live stream has no end. `completed` means the '
              'stream died and must trigger recovery.');
    });

    test('repository does not map completed to a clean stop', () {
      final repo =
          File('lib/data/repositories/stream_repository.dart').readAsStringSync();
      final idx = repo.indexOf('case AudioProcessingState.completed:');
      expect(idx, greaterThan(-1));
      final branch = stripComments(repo.substring(idx, idx + 1600));
      expect(branch, isNot(contains('_updateState(StreamState.stopped)')),
          reason: 'Mapping completed to `stopped` treats a dead stream exactly '
              'like the user pressing stop: no notice, no error, silence. '
              'This is what made the bug invisible.');
      expect(branch, contains('_onPlayerError()'),
          reason: 'completed must route to the error classifier so an '
              'exhausted reconnect actually reaches the listener.');
    });
  });
}
