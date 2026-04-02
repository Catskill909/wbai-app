import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../services/logger_service.dart';
import '../../data/repositories/stream_repository.dart';

/// Represents different types of audio commands
enum AudioCommandType {
  play,
  pause,
  stop,
  retry,
  reset,
}

/// Represents the source of an audio command
enum AudioCommandSource {
  ui,
  lockscreen,  // iOS lockscreen controls
  networkRecovery,
  networkLoss,
  errorRecovery,
  system,
}

/// Represents a queued audio command
class AudioCommand {
  final AudioCommandType type;
  final AudioCommandSource source;
  final DateTime timestamp;
  final Map<String, dynamic>? extras;
  final Completer<void> completer;

  AudioCommand({
    required this.type,
    required this.source,
    this.extras,
  }) : timestamp = DateTime.now(),
       completer = Completer<void>();

  @override
  String toString() => 'AudioCommand(type: $type, source: $source, timestamp: $timestamp)';
}

/// Global audio state that prevents race conditions and stuck states
enum GlobalAudioState {
  idle,
  connecting,
  buffering,
  playing,
  paused,
  error,
  networkError,
  serverError,        // Audio server unavailable
  serverUnavailable,  // Server down/maintenance
  streamNotFound,     // Stream endpoint not found
  resetting,
}

/// Centralized audio state manager to prevent race conditions and stuck states
class AudioStateManager extends ChangeNotifier {
  static final AudioStateManager _instance = AudioStateManager._internal();
  factory AudioStateManager() => _instance;
  AudioStateManager._internal();

  // Command queue to prevent concurrent operations
  final Queue<AudioCommand> _commandQueue = Queue<AudioCommand>();
  bool _processingCommand = false;

  // Global state tracking
  GlobalAudioState _currentState = GlobalAudioState.idle;
  String? _errorMessage;
  DateTime? _lastStateChange;
  AudioCommandSource? _lastCommandSource;
  
  // Network state tracking
  bool _isOnline = true;
  bool _wasAttemptingPlayWhenOffline = false;
  
  // Timeout handling
  Timer? _commandTimeoutTimer;
  Timer? _bufferingTimeoutTimer;
  static const Duration _commandTimeout = Duration(seconds: 10);
  static const Duration _bufferingTimeout = Duration(seconds: 30);

  // PHASE 1: State divergence tracking
  StreamSubscription? _streamRepositorySubscription;

  // PHASE 2: StreamRepository injection for command redirection
  StreamRepository? _streamRepository;

  // Getters
  GlobalAudioState get currentState => _currentState;
  String? get errorMessage => _errorMessage;
  bool get isProcessingCommand => _processingCommand;
  bool get isOnline => _isOnline;
  bool get wasAttemptingPlayWhenOffline => _wasAttemptingPlayWhenOffline;
  AudioCommandSource? get lastCommandSource => _lastCommandSource;
  DateTime? get lastStateChange => _lastStateChange;

  /// Queue an audio command to prevent race conditions
  Future<void> enqueueCommand(AudioCommand command) async {
    // PHASE 2: Log that commands are now routed through StreamRepository
    LoggerService.info('🎛️ PHASE 2: AudioStateManager.enqueueCommand() - now routes through StreamRepository');
    LoggerService.info('🎛️ AudioStateManager: Enqueuing ${command.type} from ${command.source}');
    
    // Special handling for urgent commands
    if (command.type == AudioCommandType.reset) {
      _commandQueue.clear();
      _commandQueue.addFirst(command);
    } else {
      _commandQueue.add(command);
    }

    // Start processing if not already doing so
    if (!_processingCommand) {
      _processCommandQueue();
    }
  }

  /// Process the command queue sequentially
  Future<void> _processCommandQueue() async {
    if (_processingCommand || _commandQueue.isEmpty) return;

    _processingCommand = true;
    
    try {
      while (_commandQueue.isNotEmpty) {
        final command = _commandQueue.removeFirst();
        await _executeCommand(command);
      }
    } catch (e) {
      LoggerService.audioError('Error processing command queue', e);
    } finally {
      _processingCommand = false;
    }
  }

  /// Execute a single audio command
  Future<void> _executeCommand(AudioCommand command) async {
    try {
      LoggerService.info('🎛️ AudioStateManager: Executing ${command.type} from ${command.source}');
      
      _lastCommandSource = command.source;
      _lastStateChange = DateTime.now();
      
      // Set timeout for command execution
      _commandTimeoutTimer?.cancel();
      _commandTimeoutTimer = Timer(_commandTimeout, () {
        LoggerService.audioError('Command timeout: ${command.type}', null);
        _handleCommandTimeout(command);
      });

      switch (command.type) {
        case AudioCommandType.play:
          await _executePlayCommand(command);
          break;
        case AudioCommandType.pause:
          await _executePauseCommand(command);
          break;
        case AudioCommandType.stop:
          await _executeStopCommand(command);
          break;
        case AudioCommandType.retry:
          await _executeRetryCommand(command);
          break;
        case AudioCommandType.reset:
          await _executeResetCommand(command);
          break;
      }

      _commandTimeoutTimer?.cancel();
      command.completer.complete();
      
    } catch (e) {
      _commandTimeoutTimer?.cancel();
      LoggerService.audioError('Error executing ${command.type}', e);
      _updateState(GlobalAudioState.error, errorMessage: e.toString());
      command.completer.completeError(e);
    }
  }

  /// Execute play command with state validation
  Future<void> _executePlayCommand(AudioCommand command) async {
    // Validate preconditions
    if (!_isOnline) {
      _wasAttemptingPlayWhenOffline = true;
      throw Exception('Cannot play while offline');
    }

    if (_currentState == GlobalAudioState.playing) {
      LoggerService.info('🎛️ AudioStateManager: Already playing, ignoring duplicate play command');
      return;
    }

    // PHASE 2: Route command through StreamRepository (actual execution)
    if (_streamRepository != null) {
      LoggerService.info('🎛️ PHASE 2: Routing play command through StreamRepository');
      _updateState(GlobalAudioState.connecting);
      
      // Start buffering timeout
      _bufferingTimeoutTimer?.cancel();
      _bufferingTimeoutTimer = Timer(_bufferingTimeout, () {
        LoggerService.audioError('Buffering timeout', null);
        _handleBufferingTimeout();
      });
      
      // Actually execute the command through StreamRepository
      await _streamRepository!.play(source: command.source);
      LoggerService.info('🎛️ PHASE 2: Play command executed through StreamRepository');
    } else {
      // Fallback to Phase 1 behavior (for safety)
      LoggerService.warning('🎛️ PHASE 2: StreamRepository not available, using fallback behavior');
      _updateState(GlobalAudioState.connecting);
      
      // Start buffering timeout
      _bufferingTimeoutTimer?.cancel();
      _bufferingTimeoutTimer = Timer(_bufferingTimeout, () {
        LoggerService.audioError('Buffering timeout', null);
        _handleBufferingTimeout();
      });
      
      LoggerService.info('🎛️ AudioStateManager: Play command processed, state updated to connecting');
    }
  }

  /// Execute pause command
  Future<void> _executePauseCommand(AudioCommand command) async {
    if (_currentState == GlobalAudioState.paused || _currentState == GlobalAudioState.idle) {
      LoggerService.info('🎛️ AudioStateManager: Already paused/idle, ignoring duplicate pause command');
      return;
    }

    // PHASE 2: Route command through StreamRepository (actual execution)
    if (_streamRepository != null) {
      LoggerService.info('🎛️ PHASE 2: Routing pause command through StreamRepository');
      _updateState(GlobalAudioState.paused);
      _bufferingTimeoutTimer?.cancel();
      
      // Actually execute the command through StreamRepository
      await _streamRepository!.pause(source: command.source);
      LoggerService.info('🎛️ PHASE 2: Pause command executed through StreamRepository');
    } else {
      // Fallback to Phase 1 behavior (for safety)
      LoggerService.warning('🎛️ PHASE 2: StreamRepository not available, using fallback behavior');
      _updateState(GlobalAudioState.paused);
      _bufferingTimeoutTimer?.cancel();
      
      LoggerService.info('🎛️ AudioStateManager: Pause command processed, state updated to paused');
    }
  }

  /// Execute stop command
  Future<void> _executeStopCommand(AudioCommand command) async {
    // PHASE 2: Route command through StreamRepository (actual execution)
    if (_streamRepository != null) {
      LoggerService.info('🎛️ PHASE 2: Routing stop command through StreamRepository');
      _updateState(GlobalAudioState.idle);
      _bufferingTimeoutTimer?.cancel();
      _errorMessage = null;
      
      // Actually execute the command through StreamRepository
      await _streamRepository!.stop();
      LoggerService.info('🎛️ PHASE 2: Stop command executed through StreamRepository');
    } else {
      // Fallback to Phase 1 behavior (for safety)
      LoggerService.warning('🎛️ PHASE 2: StreamRepository not available, using fallback behavior');
      _updateState(GlobalAudioState.idle);
      _bufferingTimeoutTimer?.cancel();
      _errorMessage = null;
    }
  }

  /// Execute retry command
  Future<void> _executeRetryCommand(AudioCommand command) async {
    LoggerService.info('🎛️ AudioStateManager: Executing retry command');
    
    // Clear error state
    _errorMessage = null;
    
    // PHASE 2: Route command through StreamRepository (actual execution)
    if (_streamRepository != null) {
      LoggerService.info('🎛️ PHASE 2: Routing retry command through StreamRepository');
      
      // Reset and then play through StreamRepository
      await _executeResetCommand(command);
      await _streamRepository!.play(source: AudioCommandSource.errorRecovery);
      LoggerService.info('🎛️ PHASE 2: Retry command executed through StreamRepository');
    } else {
      // Fallback to Phase 1 behavior (for safety)
      LoggerService.warning('🎛️ PHASE 2: StreamRepository not available, using fallback behavior');
      
      // Reset and then play
      await _executeResetCommand(command);
      await _executePlayCommand(AudioCommand(
        type: AudioCommandType.play,
        source: AudioCommandSource.errorRecovery,
      ));
    }
  }

  /// Execute reset command - nuclear option for stuck states
  Future<void> _executeResetCommand(AudioCommand command) async {
    LoggerService.info('🎛️ AudioStateManager: Executing nuclear reset from ${command.source}');
    
    _updateState(GlobalAudioState.resetting);
    
    // Cancel all timers
    _commandTimeoutTimer?.cancel();
    _bufferingTimeoutTimer?.cancel();
    
    // Clear error state
    _errorMessage = null;
    _wasAttemptingPlayWhenOffline = false;
    
    // For network loss resets, we need to ensure complete audio pipeline reset
    if (command.source == AudioCommandSource.networkLoss) {
      LoggerService.info('🎛️ AudioStateManager: Network loss reset - triggering complete audio pipeline reset');
      
      // PHASE 2: Route reset through StreamRepository (actual execution)
      if (_streamRepository != null) {
        LoggerService.info('🎛️ PHASE 2: Routing network loss reset through StreamRepository');
        await _streamRepository!.stopAndColdReset();
        LoggerService.info('🎛️ PHASE 2: Network loss reset executed through StreamRepository');
      } else {
        // Fallback to Phase 1 behavior (for safety)
        LoggerService.warning('🎛️ PHASE 2: StreamRepository not available for network loss reset');
        // The StreamRepository.stopAndColdReset() will be called by the repository
        // when it receives the reset command through the audio handler
      }
    }
    
    // Brief delay to ensure all systems reset
    await Future.delayed(const Duration(milliseconds: 500));
    
    _updateState(GlobalAudioState.idle);
  }

  /// Update network connectivity state
  void updateNetworkState(bool isOnline) {
    final wasOnline = _isOnline;
    _isOnline = isOnline;
    
    LoggerService.info('🎛️ AudioStateManager: Network state changed: $wasOnline → $isOnline');
    
    if (!wasOnline && isOnline) {
      // Network recovered
      _handleNetworkRecovery();
    } else if (wasOnline && !isOnline) {
      // Network lost
      _handleNetworkLoss();
    }
    
    notifyListeners();
  }

  /// Handle network recovery
  void _handleNetworkRecovery() {
    LoggerService.info('🎛️ AudioStateManager: Network recovered');
    
    // Clear network error state
    if (_currentState == GlobalAudioState.networkError) {
      _updateState(GlobalAudioState.idle);
      _errorMessage = null;
    }
    
    // Auto-retry if user was attempting to play
    if (_wasAttemptingPlayWhenOffline) {
      LoggerService.info('🎛️ AudioStateManager: Auto-retrying play after network recovery');
      _wasAttemptingPlayWhenOffline = false;
      
      enqueueCommand(AudioCommand(
        type: AudioCommandType.play,
        source: AudioCommandSource.networkRecovery,
      ));
    }
  }

  /// Handle network loss
  void _handleNetworkLoss() {
    LoggerService.info('🎛️ AudioStateManager: Network lost');
    
    if (_currentState == GlobalAudioState.playing || 
        _currentState == GlobalAudioState.connecting ||
        _currentState == GlobalAudioState.buffering) {
      _wasAttemptingPlayWhenOffline = true;
      _updateState(GlobalAudioState.networkError, 
                  errorMessage: 'Network connection lost');
    }
  }

  /// Trigger complete audio reset when network is lost
  /// This ensures the app returns to pristine startup state
  void triggerNetworkLossReset() {
    LoggerService.info('🎛️ AudioStateManager: Triggering complete reset due to network loss');
    
    enqueueCommand(AudioCommand(
      type: AudioCommandType.reset,
      source: AudioCommandSource.networkLoss,
    ));
  }

  /// Handle server-specific errors (server down, stream not found, etc.)
  /// This resets audio controls but doesn't trigger network recovery logic
  void handleServerError(GlobalAudioState serverErrorState, String errorMessage) {
    LoggerService.info('🎛️ AudioStateManager: Handling server error: $serverErrorState');
    
    // Clear any pending commands
    _commandQueue.clear();
    
    // Cancel timeouts
    _commandTimeoutTimer?.cancel();
    _bufferingTimeoutTimer?.cancel();
    
    // Update to server error state
    _updateState(serverErrorState, errorMessage: errorMessage);
    
    // Clear processing flags
    _processingCommand = false;
    
    // Notify listeners to update UI (reset play button, etc.)
    notifyListeners();
  }

  /// Reset from server error state - clears error and returns to idle
  void clearServerError() {
    LoggerService.info('🎛️ AudioStateManager: Clearing server error state');
    
    if (_currentState == GlobalAudioState.serverError ||
        _currentState == GlobalAudioState.serverUnavailable ||
        _currentState == GlobalAudioState.streamNotFound) {
      _updateState(GlobalAudioState.idle);
      _errorMessage = null;
    }
  }

  /// Handle command timeout
  void _handleCommandTimeout(AudioCommand command) {
    LoggerService.audioError('Command ${command.type} timed out', null);
    _updateState(GlobalAudioState.error, 
                errorMessage: 'Audio command timed out. Tap retry to continue.');
  }

  /// Handle buffering timeout
  void _handleBufferingTimeout() {
    LoggerService.audioError('Buffering timed out', null);
    _updateState(GlobalAudioState.error, 
                errorMessage: 'Stream is taking too long to load. Check your connection and retry.');
  }

  /// Update the current state and notify listeners
  void _updateState(GlobalAudioState newState, {String? errorMessage}) {
    final oldState = _currentState;
    _currentState = newState;
    _errorMessage = errorMessage;
    _lastStateChange = DateTime.now();
    
    LoggerService.info('🎛️ AudioStateManager: State changed: $oldState → $newState');
    
    if (errorMessage != null) {
      LoggerService.audioError('Audio state error: $errorMessage', null);
    }
    
    notifyListeners();
  }

  /// External method for audio handler to report state changes
  void reportAudioHandlerState({
    required bool isPlaying,
    required bool isBuffering,
    String? error,
  }) {
    if (error != null) {
      _updateState(GlobalAudioState.error, errorMessage: error);
      return;
    }

    if (isBuffering) {
      if (_currentState != GlobalAudioState.buffering) {
        _updateState(GlobalAudioState.buffering);
      }
    } else if (isPlaying) {
      _bufferingTimeoutTimer?.cancel();
      if (_currentState != GlobalAudioState.playing) {
        _updateState(GlobalAudioState.playing);
      }
    } else {
      _bufferingTimeoutTimer?.cancel();
      if (_currentState == GlobalAudioState.playing || _currentState == GlobalAudioState.buffering) {
        _updateState(GlobalAudioState.paused);
      }
    }
  }

  /// Get user-friendly state description
  String getStateDescription() {
    switch (_currentState) {
      case GlobalAudioState.idle:
        return 'Ready to play';
      case GlobalAudioState.connecting:
        return 'Connecting...';
      case GlobalAudioState.buffering:
        return 'Buffering...';
      case GlobalAudioState.playing:
        return 'Playing';
      case GlobalAudioState.paused:
        return 'Paused';
      case GlobalAudioState.error:
        return _errorMessage ?? 'Error occurred';
      case GlobalAudioState.networkError:
        return 'No network connection';
      case GlobalAudioState.serverError:
        return 'Audio server unavailable';
      case GlobalAudioState.serverUnavailable:
        return 'Server temporarily unavailable';
      case GlobalAudioState.streamNotFound:
        return 'Stream not found';
      case GlobalAudioState.resetting:
        return 'Resetting...';
    }
  }

  /// Check if play button should be enabled
  bool get canPlay => _isOnline && 
                     _currentState != GlobalAudioState.connecting &&
                     _currentState != GlobalAudioState.buffering &&
                     _currentState != GlobalAudioState.resetting &&
                     _currentState != GlobalAudioState.serverError &&
                     _currentState != GlobalAudioState.serverUnavailable &&
                     _currentState != GlobalAudioState.streamNotFound &&
                     !_processingCommand;

  /// Check if pause button should be enabled
  bool get canPause => _currentState == GlobalAudioState.playing && !_processingCommand;

  /// Check if loading indicator should be shown
  bool get shouldShowLoading => _currentState == GlobalAudioState.connecting ||
                               _currentState == GlobalAudioState.buffering ||
                               _currentState == GlobalAudioState.resetting ||
                               _processingCommand;

  // PHASE 1: State divergence tracking and StreamRepository listener
  
  /// Map StreamState to GlobalAudioState for comparison
  GlobalAudioState _mapStreamStateToGlobal(StreamState streamState) {
    switch (streamState) {
      case StreamState.initial:
        return GlobalAudioState.idle;
      case StreamState.loading:
      case StreamState.connecting:
        return GlobalAudioState.connecting;
      case StreamState.buffering:
        return GlobalAudioState.buffering;
      case StreamState.playing:
        return GlobalAudioState.playing;
      case StreamState.paused:
      case StreamState.stopped:
        return GlobalAudioState.paused;
      case StreamState.error:
        return GlobalAudioState.error;
    }
  }

  /// Log state divergence between AudioStateManager and StreamRepository
  void _logStateDivergence(StreamState streamState) {
    final expectedGlobalState = _mapStreamStateToGlobal(streamState);
    if (_currentState != expectedGlobalState) {
      LoggerService.warning(
        '🔄 STATE DIVERGENCE: AudioStateManager=${_currentState.name}, '
        'StreamRepository=${streamState.name} (expected: ${expectedGlobalState.name})'
      );
    }
  }

  /// Start listening to StreamRepository state changes (Phase 1 safety)
  void startListeningToStreamRepository(StreamRepository streamRepository) {
    LoggerService.info('🔄 PHASE 1: AudioStateManager starting to listen to StreamRepository');
    
    // PHASE 2: Store StreamRepository reference for command redirection
    _streamRepository = streamRepository;
    LoggerService.info('🔄 PHASE 2: StreamRepository injected into AudioStateManager');
    
    _streamRepositorySubscription?.cancel();
    _streamRepositorySubscription = streamRepository.stateStream.listen((streamState) {
      _logStateDivergence(streamState);
      // Phase 2: Commands now route through StreamRepository for actual execution
    });
  }

  /// Stop listening to StreamRepository (cleanup)
  void stopListeningToStreamRepository() {
    _streamRepositorySubscription?.cancel();
    _streamRepositorySubscription = null;
    LoggerService.info('🔄 AudioStateManager stopped listening to StreamRepository');
  }


  /// Dispose resources
  @override
  void dispose() {
    _commandTimeoutTimer?.cancel();
    _bufferingTimeoutTimer?.cancel();
    // PHASE 1: Clean up StreamRepository subscription
    stopListeningToStreamRepository();
    super.dispose();
  }
}
