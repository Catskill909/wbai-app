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

  ConnectivityCubit({
    required ConnectivityService service,
    StreamRepository? streamRepository,
  })  : _service = service,
        _streamRepository = streamRepository,
        super(ConnectivityState.initial());

  void initialize() {
    LoggerService.info('🌐 ConnectivityCubit: Initializing connectivity monitoring');
    _sub?.cancel();
    _sub = _service.connectivityStream().listen((isOnline) async {
      final wasOnline = state.isOnline;
      final wasFirstRun = state.firstRun;
      
      // Update connectivity state
      emit(state.copyWith(
        isOnline: isOnline,
        checking: false,
        firstRun: false,
      ));
      
      // Log network state changes for debugging
      if (!wasFirstRun && wasOnline != isOnline) {
        if (isOnline) {
          LoggerService.info('🌐 ConnectivityCubit: Network recovered - modal will be removed, no audio changes');
          // USER'S SOLUTION: Network recovery only removes modal, doesn't touch audio
        } else {
          LoggerService.info('🌐 ConnectivityCubit: Network lost - resetting audio to initial state immediately');
          
          // USER'S SOLUTION: Reset audio to initial state IMMEDIATELY when network is lost
          if (_streamRepository != null) {
            try {
              await _streamRepository.pause(source: AudioCommandSource.networkLoss);
              LoggerService.info('🌐 ConnectivityCubit: Audio reset to initial state completed');
            } catch (e) {
              LoggerService.streamError('Error resetting audio on network loss', e);
            }
          }
        }
      }
    });
  }

  Future<void> checkNow() async {
    emit(state.copyWith(checking: true));
    final online = await _service.hasInternet();
    emit(state.copyWith(
      isOnline: online,
      checking: false,
      firstRun: false,
    ));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
