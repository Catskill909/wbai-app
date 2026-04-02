import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/logger_service.dart';
import '../../core/services/audio_state_manager.dart';
import '../../data/repositories/stream_repository.dart';
import '../../domain/models/stream_metadata.dart';

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
  final String? errorMessage;
  final bool isServerError;
  UpdatePlaybackState(this.state, {this.errorMessage, this.isServerError = false});
}

class ClearServerError extends StreamEvent {}

// States
class StreamBlocState {
  final StreamState playbackState;
  final StreamMetadata? metadata;
  final String? errorMessage;
  final bool showServerErrorModal;

  StreamBlocState({
    required this.playbackState,
    this.metadata,
    this.errorMessage,
    this.showServerErrorModal = false,
  });

  StreamBlocState copyWith({
    StreamState? playbackState,
    StreamMetadata? metadata,
    String? errorMessage,
    bool? showServerErrorModal,
  }) {
    return StreamBlocState(
      playbackState: playbackState ?? this.playbackState,
      metadata: metadata ?? this.metadata,
      errorMessage: errorMessage ?? this.errorMessage,
      showServerErrorModal: showServerErrorModal ?? this.showServerErrorModal,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is StreamBlocState &&
        other.playbackState == playbackState &&
        other.metadata == metadata &&
        other.errorMessage == errorMessage &&
        other.showServerErrorModal == showServerErrorModal;
  }

  @override
  int get hashCode =>
      playbackState.hashCode ^ 
      metadata.hashCode ^ 
      errorMessage.hashCode ^
      showServerErrorModal.hashCode;
}

class StreamBloc extends Bloc<StreamEvent, StreamBlocState> {
  final StreamRepository _repository;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _metadataSubscription;

  StreamBloc({
    required StreamRepository repository,
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
    on<ClearServerError>(_onClearServerError);
  }

  void _initializeSubscriptions() {
    // Listen to repository state changes
    _stateSubscription = _repository.stateStream.listen(
      (streamState) {
        if (streamState == StreamState.error) {
          add(UpdatePlaybackState(
            streamState,
            errorMessage: 'Stream playback error occurred',
          ));
        } else {
          add(UpdatePlaybackState(streamState));
        }
      },
    );

    // Listen to metadata updates
    _metadataSubscription = _repository.metadataStream.listen(
      (metadata) {
        add(UpdateMetadata(metadata));
      },
    );
  }

  Future<void> _onStartStream(
    StartStream event,
    Emitter<StreamBlocState> emit,
  ) async {
    try {
      // Clear any previous error state when starting a new stream
      emit(state.copyWith(
        errorMessage: null,
        showServerErrorModal: false,
      ));
      
      await _repository.play(source: AudioCommandSource.ui);
    } catch (e) {
      emit(state.copyWith(
        playbackState: StreamState.error,
        errorMessage: 'Failed to start stream: $e',
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
      emit(state.copyWith(
        playbackState: StreamState.error,
        errorMessage: 'Failed to pause stream: $e',
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
      emit(state.copyWith(
        playbackState: StreamState.error,
        errorMessage: 'Failed to stop stream: $e',
      ));
    }
  }

  Future<void> _onRetryStream(
    RetryStream event,
    Emitter<StreamBlocState> emit,
  ) async {
    try {
      await _repository.retry();
    } catch (e) {
      emit(state.copyWith(
        playbackState: StreamState.error,
        errorMessage: 'Failed to retry stream: $e',
      ));
    }
  }

  void _onUpdateMetadata(
    UpdateMetadata event,
    Emitter<StreamBlocState> emit,
  ) {
    LoggerService.debug(
        'Updating metadata in bloc: ${event.metadata.toString()}');
    emit(state.copyWith(metadata: event.metadata));
    LoggerService.debug(
        'New bloc state metadata: ${state.metadata?.toString()}');
  }

  void _onUpdatePlaybackState(
    UpdatePlaybackState event,
    Emitter<StreamBlocState> emit,
  ) {
    emit(state.copyWith(
      playbackState: event.state,
      errorMessage: event.errorMessage,
      showServerErrorModal: event.isServerError,
    ));
  }

  void _onClearServerError(
    ClearServerError event,
    Emitter<StreamBlocState> emit,
  ) {
    _repository.clearServerError();
    emit(state.copyWith(
      showServerErrorModal: false,
      errorMessage: null,
    ));
  }

  @override
  Future<void> close() async {
    await _stateSubscription?.cancel();
    await _metadataSubscription?.cancel();
    await super.close();
  }
}
