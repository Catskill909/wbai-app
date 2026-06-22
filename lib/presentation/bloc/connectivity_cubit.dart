import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/logger_service.dart';
import '../../core/services/audio_state_manager.dart';
import '../../data/repositories/stream_repository.dart';

class ConnectivityState extends Equatable {
  final bool isOnline;
  final bool checking;
  final bool firstRun;

  const ConnectivityState({
    required this.isOnline,
    required this.checking,
    required this.firstRun,
  });

  factory ConnectivityState.initial() => const ConnectivityState(
        isOnline: true, // optimistic until checked
        checking: true,
        firstRun: true,
      );

  ConnectivityState copyWith({
    bool? isOnline,
    bool? checking,
    bool? firstRun,
  }) => ConnectivityState(
        isOnline: isOnline ?? this.isOnline,
        checking: checking ?? this.checking,
        firstRun: firstRun ?? this.firstRun,
      );

  @override
  List<Object?> get props => [isOnline, checking, firstRun];
}

class ConnectivityCubit extends Cubit<ConnectivityState> {
  final ConnectivityService _service;
  final StreamRepository? _streamRepository;
  StreamSubscription<bool>? _sub;

  // SAFETY NET: while offline, actively re-probe on a timer instead of waiting
  // for another transport-change event (which may never come — e.g. Airplane
  // Mode off leaves the transport "connected" the whole time). Without this the
  // offline modal could latch forever and freeze the whole app.
  Timer? _recoveryPoll;
  static const Duration _recoveryInterval = Duration(seconds: 3);
  bool _probing = false;

  ConnectivityCubit({
    required ConnectivityService service,
    StreamRepository? streamRepository,
  })  : _service = service,
        _streamRepository = streamRepository,
        super(ConnectivityState.initial());

  void initialize() {
    _sub?.cancel();
    _sub = _service.connectivityStream().listen(_applyConnectivity);
  }

  /// Single entry point for every connectivity update (stream OR recovery poll),
  /// so the network-loss / network-recovery side effects run no matter which
  /// path detected the change.
  Future<void> _applyConnectivity(bool isOnline) async {
    final wasOnline = state.isOnline;
    final wasFirstRun = state.firstRun;

    emit(state.copyWith(
      isOnline: isOnline,
      checking: false,
      firstRun: false,
    ));

    // SAFETY NET: poll for recovery while offline, stop once back online.
    if (isOnline) {
      _stopRecoveryPoll();
    } else {
      _startRecoveryPoll();
    }

    if (!wasFirstRun && wasOnline != isOnline) {
      if (isOnline) {
        await _onNetworkRecovered();
      } else {
        await _onNetworkLost();
      }
    }
  }

  /// Network lost: pause playback so we're not feeding a dead socket.
  Future<void> _onNetworkLost() async {
    LoggerService.info('🌐 ConnectivityCubit: Network lost - pausing audio');
    if (_streamRepository == null) return;
    try {
      await _streamRepository.pause(source: AudioCommandSource.networkLoss);
    } catch (e) {
      LoggerService.streamError('Error pausing audio on network loss', e);
    }
  }

  /// Network recovered: reset the audio pipeline to a cold, playable state.
  /// just_audio's iOS AVPlayer does NOT auto-reconnect to a live radio stream
  /// after a network drop (ryanheise/just_audio#1277) — the old AVPlayerItem is
  /// dead, so a plain play() does nothing. resetToColdStart() (via
  /// stopAndColdReset) calls setAudioSource() with a fresh URL, creating a new
  /// player item, so the next play() works cleanly. Metadata is preserved so
  /// the show info / lockscreen don't blank out.
  Future<void> _onNetworkRecovered() async {
    LoggerService.info('🌐 ConnectivityCubit: Network recovered - cold-resetting audio pipeline');
    if (_streamRepository == null) return;
    try {
      await _streamRepository.stopAndColdReset(preserveMetadata: true);
      LoggerService.info('🌐 ConnectivityCubit: Audio pipeline reset - ready to play');
    } catch (e) {
      LoggerService.streamError('Error resetting audio on network recovery', e);
    }
  }

  Future<void> checkNow() async {
    emit(state.copyWith(checking: true));
    final online = await _service.hasInternet();
    await _applyConnectivity(online);
  }

  /// Start polling for internet recovery while offline. Idempotent.
  void _startRecoveryPoll() {
    if (_recoveryPoll != null) return;
    LoggerService.info('🌐 ConnectivityCubit: Starting recovery poll (offline)');
    _recoveryPoll = Timer.periodic(_recoveryInterval, (_) async {
      if (_probing || isClosed) return;
      _probing = true;
      try {
        final online = await _service.hasInternet();
        if (online && !isClosed) {
          LoggerService.info('🌐 ConnectivityCubit: Recovery poll detected internet - back online');
          // Route through _applyConnectivity so the recovery audio reset runs.
          // _stopRecoveryPoll() is called inside _applyConnectivity.
          await _applyConnectivity(true);
        }
      } catch (e) {
        LoggerService.error('🌐 ConnectivityCubit: Recovery poll error', e);
      } finally {
        _probing = false;
      }
    });
  }

  void _stopRecoveryPoll() {
    if (_recoveryPoll == null) return;
    LoggerService.info('🌐 ConnectivityCubit: Stopping recovery poll (online)');
    _recoveryPoll?.cancel();
    _recoveryPoll = null;
  }

  /// Expose the current online state for the recovery poll closure.
  bool get isOnline => state.isOnline;

  @override
  Future<void> close() async {
    _stopRecoveryPoll();
    await _sub?.cancel();
    return super.close();
  }
}
