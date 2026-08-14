import 'package:flutter_test/flutter_test.dart';
import 'package:wbai_radio/data/repositories/stream_repository.dart';
import 'package:wbai_radio/domain/models/stream_notice.dart';
import 'package:wbai_radio/presentation/bloc/stream_bloc.dart';

/// Guards the notice state machine — the piece that decides whether a listener
/// is told anything at all when audio fails to start. Its predecessor went
/// silent on network faults precisely because nothing pinned this down.
void main() {
  group('StreamNotice', () {
    test('outage and connection notices are not interchangeable', () {
      expect(const StreamNotice.outage(), isNot(const StreamNotice.connection()));
      expect(const StreamNotice.outage().kind, StreamNoticeKind.outage);
      expect(const StreamNotice.connection().kind, StreamNoticeKind.connection);
    });

    test('value equality includes the detail line', () {
      expect(
        const StreamNotice.outage(detail: 'Stream not found on server'),
        const StreamNotice.outage(detail: 'Stream not found on server'),
      );
      expect(
        const StreamNotice.outage(detail: 'a'),
        isNot(const StreamNotice.outage(detail: 'b')),
      );
    });
  });

  group('StreamBlocState.copyWith', () {
    final base = StreamBlocState(
      playbackState: StreamState.playing,
      notice: const StreamNotice.outage(detail: 'Server error occurred'),
    );

    test('omitting notice leaves it untouched', () {
      final next = base.copyWith(playbackState: StreamState.error);
      expect(next.notice, base.notice);
      expect(next.playbackState, StreamState.error);
    });

    test('clearNotice actually clears it', () {
      // The old sentinel-free `notice ?? this.notice` silently ignored an
      // explicit null, which is what left a dismissed notice stuck on screen.
      expect(base.copyWith(clearNotice: true).notice, isNull);
    });

    test('clearNotice wins over a supplied notice', () {
      final next = base.copyWith(
        notice: const StreamNotice.connection(),
        clearNotice: true,
      );
      expect(next.notice, isNull);
    });

    test('a new notice replaces the old one', () {
      expect(
        base.copyWith(notice: const StreamNotice.connection()).notice,
        const StreamNotice.connection(),
      );
    });

    test('hasNotice tracks presence', () {
      expect(base.hasNotice, isTrue);
      expect(base.copyWith(clearNotice: true).hasNotice, isFalse);
    });
  });

  group('StreamBlocState equality', () {
    test('states differing only by notice are not equal', () {
      final a = StreamBlocState(
        playbackState: StreamState.error,
        notice: const StreamNotice.outage(),
      );
      final b = StreamBlocState(
        playbackState: StreamState.error,
        notice: const StreamNotice.connection(),
      );
      // If these compared equal, bloc would swallow the emit and the modal
      // would never switch variants.
      expect(a, isNot(b));
      expect(a, StreamBlocState(
        playbackState: StreamState.error,
        notice: const StreamNotice.outage(),
      ));
    });

    test('clearing a notice produces a distinct state', () {
      final withNotice = StreamBlocState(
        playbackState: StreamState.error,
        notice: const StreamNotice.outage(),
      );
      expect(withNotice, isNot(withNotice.copyWith(clearNotice: true)));
    });
  });
}
