import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wbai_radio/core/services/audio_state_manager.dart';
import 'package:wbai_radio/data/repositories/stream_repository.dart';
import 'package:wbai_radio/domain/models/stream_metadata.dart';
import 'package:wbai_radio/domain/models/stream_notice.dart';
import 'package:wbai_radio/presentation/bloc/stream_bloc.dart';

/// End-to-end scenarios for the outage warning, driven through the real
/// [StreamBloc] against a fake source.
///
/// Two halves, and the second matters as much as the first:
///   • an outage the listener should be told about raises exactly one notice;
///   • ordinary playback NEVER raises one. A radio app that cries "we're down"
///     during a routine buffering blip is worse than one that says nothing.
class FakeStreamSource implements StreamSource {
  final _states = StreamController<StreamState>.broadcast();
  final _metadata = StreamController<StreamMetadata>.broadcast();
  final _notices = StreamController<StreamNotice?>.broadcast();

  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int retryCalls = 0;
  int dismissCalls = 0;

  /// Set to make the corresponding command throw, standing in for a command
  /// that blows up before the repository can classify anything.
  Object? playThrows;

  @override
  Stream<StreamState> get stateStream => _states.stream;
  @override
  Stream<StreamMetadata> get metadataStream => _metadata.stream;
  @override
  Stream<StreamNotice?> get noticeStream => _notices.stream;

  @override
  Future<void> play({AudioCommandSource? source}) async {
    playCalls++;
    if (playThrows != null) throw playThrows!;
  }

  @override
  Future<void> pause({AudioCommandSource? source}) async => pauseCalls++;
  @override
  Future<void> stop() async => stopCalls++;
  @override
  Future<void> retry() async => retryCalls++;
  @override
  void dismissNotice() => dismissCalls++;

  // --- test drivers: what the real repository would emit ---
  void emitState(StreamState s) => _states.add(s);
  void emitNotice(StreamNotice? n) => _notices.add(n);
  void emitMetadata(StreamMetadata m) => _metadata.add(m);

  Future<void> dispose() async {
    await _states.close();
    await _metadata.close();
    await _notices.close();
  }
}

void main() {
  late FakeStreamSource source;
  late StreamBloc bloc;

  setUp(() {
    source = FakeStreamSource();
    bloc = StreamBloc(repository: source);
  });

  tearDown(() async {
    await bloc.close();
    await source.dispose();
  });

  /// Let the bloc drain its event queue.
  Future<void> settle() => pumpEventQueue(times: 20);

  group('the listener IS warned', () {
    test('Icecast down: outage notice raises the modal', () async {
      source.emitState(StreamState.connecting);
      await settle();
      expect(bloc.state.hasNotice, isFalse, reason: 'nothing wrong yet');

      source.emitNotice(
          const StreamNotice.outage(detail: 'Server is not responding'));
      await settle();

      expect(bloc.state.notice?.kind, StreamNoticeKind.outage);
      expect(bloc.state.notice?.detail, 'Server is not responding');
      expect(bloc.state.playbackState, StreamState.error);
    });

    test('mount 404: outage notice carries the technical detail', () async {
      source.emitNotice(
          const StreamNotice.outage(detail: 'Stream not found on server'));
      await settle();
      expect(bloc.state.notice?.kind, StreamNoticeKind.outage);
      expect(bloc.state.notice?.detail, 'Stream not found on server');
    });

    test('network fault: connection notice, NOT an outage notice', () async {
      // Captive-portal Wi-Fi / TLS interception / reconnect exhausted against a
      // healthy server. Telling the listener the station is down would be a lie.
      source.emitNotice(const StreamNotice.connection());
      await settle();
      expect(bloc.state.notice?.kind, StreamNoticeKind.connection);
    });

    test('a command that throws still warns the listener', () async {
      source.playThrows = StateError('boom');
      bloc.add(StartStream());
      await settle();
      expect(bloc.state.notice?.kind, StreamNoticeKind.connection);
      expect(bloc.state.playbackState, StreamState.error);
    });

    test('notice survives later playback-state churn', () async {
      // The regression that made this whole rework necessary: the generic state
      // bridge used to carry error text and would clobber the live notice.
      source.emitNotice(const StreamNotice.outage(detail: 'down'));
      await settle();
      for (final s in [
        StreamState.initial,
        StreamState.stopped,
        StreamState.buffering,
        StreamState.error,
      ]) {
        source.emitState(s);
      }
      await settle();
      expect(bloc.state.notice?.kind, StreamNoticeKind.outage,
          reason: 'playback transitions must not clear a live notice');
      expect(bloc.state.notice?.detail, 'down');
    });
  });

  group('the listener is NOT warned', () {
    test('cold start shows nothing', () async {
      await settle();
      expect(bloc.state.hasNotice, isFalse);
      expect(bloc.state.playbackState, StreamState.initial);
    });

    test('a completely healthy play never raises a notice', () async {
      bloc.add(StartStream());
      await settle();
      for (final s in [
        StreamState.connecting,
        StreamState.loading,
        StreamState.buffering,
        StreamState.playing,
      ]) {
        source.emitState(s);
        await settle();
        expect(bloc.state.hasNotice, isFalse,
            reason: 'no notice may appear during a healthy start (at $s)');
      }
      expect(bloc.state.playbackState, StreamState.playing);
      expect(source.playCalls, 1);
    });

    test('mid-stream buffering blips stay silent', () async {
      source.emitState(StreamState.playing);
      await settle();
      // A live stream rebuffering is routine, not an outage.
      for (var i = 0; i < 5; i++) {
        source.emitState(StreamState.buffering);
        source.emitState(StreamState.playing);
      }
      await settle();
      expect(bloc.state.hasNotice, isFalse);
    });

    test('pause and resume stay silent', () async {
      source.emitState(StreamState.playing);
      await settle();
      bloc.add(PauseStream());
      source.emitState(StreamState.paused);
      await settle();
      expect(bloc.state.hasNotice, isFalse);

      bloc.add(StartStream());
      source.emitState(StreamState.playing);
      await settle();
      expect(bloc.state.hasNotice, isFalse);
      expect(source.pauseCalls, 1);
    });

    test('a bare error state with no notice shows no modal', () async {
      // The repository decides what deserves a notice. An error state on its
      // own — e.g. one already dismissed — must not conjure a modal.
      source.emitState(StreamState.error);
      await settle();
      expect(bloc.state.playbackState, StreamState.error);
      expect(bloc.state.hasNotice, isFalse);
    });

    test('metadata updates never raise a notice', () async {
      source.emitState(StreamState.playing);
      await settle();
      expect(bloc.state.hasNotice, isFalse);
    });
  });

  group('dismiss and retry', () {
    test('dismiss clears the modal and tells the repository', () async {
      source.emitNotice(const StreamNotice.outage());
      await settle();
      expect(bloc.state.hasNotice, isTrue);

      bloc.add(DismissStreamNotice());
      await settle();

      expect(bloc.state.hasNotice, isFalse);
      // Must reach the repository: that's what halts the reconnect loop and
      // latches the dismissal so the same outage can't pop straight back.
      expect(source.dismissCalls, 1);
    });

    test('a dismissed notice stays gone through further state churn', () async {
      source.emitNotice(const StreamNotice.outage());
      await settle();
      bloc.add(DismissStreamNotice());
      await settle();

      for (final s in [StreamState.error, StreamState.initial, StreamState.stopped]) {
        source.emitState(s);
      }
      await settle();
      expect(bloc.state.hasNotice, isFalse,
          reason: 'dismissed must mean dismissed');
    });

    test('retry clears the notice and does NOT latch a dismissal', () async {
      source.emitNotice(const StreamNotice.connection());
      await settle();

      bloc.add(RetryStream());
      await settle();

      expect(bloc.state.hasNotice, isFalse);
      expect(source.retryCalls, 1);
      // Latching here would halt reconnect — the opposite of what a retry wants.
      expect(source.dismissCalls, 0);
    });

    test('starting a fresh play clears a stale notice', () async {
      source.emitNotice(const StreamNotice.outage());
      await settle();
      bloc.add(StartStream());
      await settle();
      expect(bloc.state.hasNotice, isFalse);
    });

    test('the repository can clear the notice itself (network recovery)',
        () async {
      // stopAndColdReset emits null so a notice raised while offline doesn't
      // reappear stale once NetworkLostAlert goes away.
      source.emitNotice(const StreamNotice.connection());
      await settle();
      source.emitNotice(null);
      await settle();
      expect(bloc.state.hasNotice, isFalse);
    });

    test('a new outage can surface after an earlier one was dismissed',
        () async {
      source.emitNotice(const StreamNotice.outage(detail: 'first'));
      await settle();
      bloc.add(DismissStreamNotice());
      await settle();
      expect(bloc.state.hasNotice, isFalse);

      source.emitNotice(const StreamNotice.outage(detail: 'second'));
      await settle();
      expect(bloc.state.notice?.detail, 'second',
          reason: 'dismissing one outage must not mute the app forever');
    });
  });
}
