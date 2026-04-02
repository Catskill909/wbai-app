import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/stream_repository.dart';

// States
abstract class SleepTimerState {
  const SleepTimerState();
}

class SleepTimerInactive extends SleepTimerState {
  const SleepTimerInactive();
}

class SleepTimerScheduled extends SleepTimerState {
  final Duration total;
  const SleepTimerScheduled(this.total);
}

class SleepTimerRunning extends SleepTimerState {
  final Duration total;
  final Duration remaining;
  const SleepTimerRunning(this.total, this.remaining);
}

class SleepTimerPaused extends SleepTimerState {
  final Duration total;
  final Duration remaining;
  const SleepTimerPaused(this.total, this.remaining);
}

class SleepTimerCompleted extends SleepTimerState {
  const SleepTimerCompleted();
}

// Cubit
class SleepTimerCubit extends Cubit<SleepTimerState> {
  static const Duration _defaultDuration = Duration(minutes: 30);
  final StreamRepository _repository;
  Timer? _ticker;
  Duration _total = _defaultDuration;
  Duration _remaining = _defaultDuration;
  bool _completionTriggered = false;

  SleepTimerCubit(this._repository) : super(const SleepTimerInactive());

  Duration get total => _total;
  Duration get remaining => _remaining;

  void setMinutes(int minutes) {
    final d = Duration(minutes: minutes);
    _total = d;
    _remaining = d;
    emit(SleepTimerScheduled(d));
  }

  void start() {
    if (_remaining.inSeconds <= 0) {
      _remaining = _total;
    }
    _ticker?.cancel();
    emit(SleepTimerRunning(_total, _remaining));
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = _remaining - const Duration(seconds: 1);
      if (next.inSeconds <= 0) {
        timer.cancel();
        _remaining = Duration.zero;
        emit(const SleepTimerCompleted());
        // Execute completion side-effect exactly once regardless of UI state
        if (!_completionTriggered) {
          _completionTriggered = true;
          // Run asynchronously so we don't block state emission
          unawaited(_onComplete());
        }
      } else {
        _remaining = next;
        emit(SleepTimerRunning(_total, _remaining));
      }
    });
  }

  void pause() {
    _ticker?.cancel();
    emit(SleepTimerPaused(_total, _remaining));
  }

  void resume() {
    start();
  }

  void cancelTimer() {
    _ticker?.cancel();
    // Full reset to default
    _total = _defaultDuration;
    _remaining = _defaultDuration;
    _completionTriggered = false;
    emit(const SleepTimerInactive());
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    return super.close();
  }

  Future<void> _onComplete() async {
    try {
      await _repository.stopAndColdReset();
    } catch (_) {
      // Repository already logs errors; swallow here to avoid crashing UI
    } finally {
      // After completion, reset internal state so the next timer can start fresh
      _ticker?.cancel();
      _total = _defaultDuration;
      _remaining = _defaultDuration;
      _completionTriggered = false;
      emit(const SleepTimerInactive());
    }
  }
}
