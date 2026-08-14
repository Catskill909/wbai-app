import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/audio_state_manager.dart';
import '../../core/services/logger_service.dart';
import '../../data/repositories/stream_repository.dart';
import '../../domain/models/stream_metadata.dart';
import '../../domain/models/stream_notice.dart';

// Events
abstract class StreamEvent {}

class StartStream extends StreamEvent {}

class PauseStream extends StreamEvent {}

class StopStream extends StreamEvent {}

class RetryStream extends StreamEvent {}

class UpdateMetadata extends StreamEvent {
  final StreamMetadata metadata;
  UpdateMetadata(this.metadata);
}

class UpdatePlaybackState extends StreamEvent {
  final StreamState state;
  UpdatePlaybackState(this.state);
}

/// The repository raised (or cleared, with null) the reason audio isn't
/// playing. This is the ONLY thing that drives the notice modal.
class StreamNoticeRaised extends StreamEvent {
  final StreamNotice? notice;
  StreamNoticeRaised(this.notice);
}

/// The listener acknowledged the notice without retrying.
class DismissStreamNotice extends StreamEvent {}

// States

class StreamBlocState {
  final StreamState playbackState;
  final StreamMetadata? metadata;

  /// Why audio isn't playing, or null when there's nothing to say. This is the
  /// single source of truth for user-facing error messaging — there is no
  /// parallel `errorMessage` string, and deliberately so: the old field fed a
  /// snackbar and an inline card alongside this modal, so one outage could be
  /// announced three times, and its "is null an update or a no-op?" copyWith
  /// ambiguity was its own recurring bug.
  final StreamNotice? notice;

  StreamBlocState({
    required this.playbackState,
    this.metadata,
    this.notice,
  });

  bool get hasNotice => notice != null;

  StreamBlocState copyWith({
    StreamState? playbackState,
    StreamMetadata? metadata,
    StreamNotice? notice,
    // Explicit flag rather than a null sentinel: `notice` is nullable, and
    // "pass null to clear" vs "omit to keep" is exactly the ambiguity that bit
    // us before. Clearing is always spelled out.
    bool clearNotice = false,
  }) {
    return StreamBlocState(
      playbackState: playbackState ?? this.playbackState,
      metadata: metadata ?? this.metadata,
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is StreamBlocState &&
        other.playbackState == playbackState &&
        other.metadata == metadata &&
        other.notice == notice;
  }

  @override
  int get hashCode => Object.hash(playbackState, metadata, notice);
}

class StreamBloc extends Bloc<StreamEvent, StreamBlocState> {
  final StreamSource _repository;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _metadataSubscription;
  StreamSubscription? _noticeSubscription;

  StreamBloc({
    required StreamSource repository,
  })  : _repository = repository,
        super(
          StreamBlocState(
            playbackState: StreamState.initial,
          ),
        ) {
    _initializeSubscriptions();

    on<StartStream>(_onStartStream);
    on<PauseStream>(_onPauseStream);
    on<StopStream>(_onStopStream);
    on<RetryStream>(_onRetryStream);
    on<UpdateMetadata>(_onUpdateMetadata);
    on<UpdatePlaybackState>(_onUpdatePlaybackState);
    on<StreamNoticeRaised>(_onStreamNoticeRaised);
    on<DismissStreamNotice>(_onDismissStreamNotice);
  }

  void _initializeSubscriptions() {
    // Playback state only. It carries no error text: the reason for a failure
    // arrives on the notice channel below, so this bridge cannot clobber it.
    _stateSubscription = _repository.stateStream.listen(
      (streamState) => add(UpdatePlaybackState(streamState)),
    );

    _metadataSubscription = _repository.metadataStream.listen(
      (metadata) => add(UpdateMetadata(metadata)),
    );

    // The one channel that explains why audio isn't playing.
    _noticeSubscription = _repository.noticeStream.listen(
      (notice) => add(StreamNoticeRaised(notice)),
    );
  }

  Future<void> _onStartStream(
    StartStream event,
    Emitter<StreamBlocState> emit,
  ) async {
    try {
      // Clear any previous notice when starting a new attempt.
      emit(state.copyWith(clearNotice: true));

      await _repository.play(source: AudioCommandSource.ui);
    } catch (e) {
      LoggerService.streamError('Failed to start stream', e);
      emit(state.copyWith(
        playbackState: StreamState.error,
        notice: const StreamNotice.connection(),
      ));
    }
  }

  Future<void> _onPauseStream(
    PauseStream event,
    Emitter<StreamBlocState> emit,
  ) async {
    try {
      await _repository.pause(source: AudioCommandSource.ui);
    } catch (e) {
      LoggerService.streamError('Failed to pause stream', e);
      emit(state.copyWith(
        playbackState: StreamState.error,
        notice: const StreamNotice.connection(),
      ));
    }
  }

  Future<void> _onStopStream(
    StopStream event,
    Emitter<StreamBlocState> emit,
  ) async {
    try {
      await _repository.stop();
    } catch (e) {
      LoggerService.streamError('Failed to stop stream', e);
      emit(state.copyWith(
        playbackState: StreamState.error,
        notice: const StreamNotice.connection(),
      ));
    }
  }

  Future<void> _onRetryStream(
    RetryStream event,
    Emitter<StreamBlocState> emit,
  ) async {
    try {
      // Drop the notice as the retry starts. We deliberately do NOT go through
      // the repository's dismiss path here: that latches "user dismissed" and
      // halts reconnect, which is the opposite of what a retry wants.
      emit(state.copyWith(clearNotice: true));
      await _repository.retry();
    } catch (e) {
      LoggerService.streamError('Failed to retry stream', e);
      emit(state.copyWith(
        playbackState: StreamState.error,
        notice: const StreamNotice.connection(),
      ));
    }
  }

  void _onUpdateMetadata(
    UpdateMetadata event,
    Emitter<StreamBlocState> emit,
  ) {
    emit(state.copyWith(metadata: event.metadata));
  }

  void _onUpdatePlaybackState(
    UpdatePlaybackState event,
    Emitter<StreamBlocState> emit,
  ) {
    emit(state.copyWith(playbackState: event.state));
  }

  void _onStreamNoticeRaised(
    StreamNoticeRaised event,
    Emitter<StreamBlocState> emit,
  ) {
    final notice = event.notice;
    if (notice == null) {
      emit(state.copyWith(clearNotice: true));
      return;
    }
    emit(state.copyWith(
      playbackState: StreamState.error,
      notice: notice,
    ));
  }

  void _onDismissStreamNotice(
    DismissStreamNotice event,
    Emitter<StreamBlocState> emit,
  ) {
    _repository.dismissNotice();
    emit(state.copyWith(clearNotice: true));
  }

  @override
  Future<void> close() async {
    await _stateSubscription?.cancel();
    await _metadataSubscription?.cancel();
    await _noticeSubscription?.cancel();
    await super.close();
  }
}
