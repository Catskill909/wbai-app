import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import '../../core/services/logger_service.dart';
import '../../core/services/audio_state_manager.dart';
import '../../core/services/audio_server_health_checker.dart';
import '../../domain/models/stream_metadata.dart';
import '../../services/audio_service/wbai_audio_handler.dart';
import '../../services/metadata_service.dart';
import '../../services/metadata_service_native.dart';
import '../../services/ios_lockscreen_service.dart';
import '../../core/constants/stream_constants.dart';

enum StreamState {
  initial,
  loading,
  buffering,
  connecting,
  playing,
  paused,
  stopped,
  error,
}

class StreamRepository {
  final WBAIAudioHandler _audioHandler;
  final MetadataService _metadataService;
  final NativeMetadataService _nativeMetadataService;
  StreamSubscription? _metadataSubscription;
  StreamSubscription? _playbackStateSubscription;

  final _stateController = StreamController<StreamState>.broadcast();
  final _metadataController = StreamController<StreamMetadata>.broadcast();

  StreamState _currentState = StreamState.initial;
  StreamMetadata? _currentMetadata;

  StreamRepository({
    required WBAIAudioHandler audioHandler,
    required MetadataService metadataService,
  })  : _audioHandler = audioHandler,
        _metadataService = metadataService,
        _nativeMetadataService = NativeMetadataService() {
    _initialize();
  }

  /// Fully stop audio and return to a cold-start state.
  /// This is used by the Sleep Timer to guarantee a pristine audio state.
  ///
  /// [preserveMetadata] - If true, keeps current metadata and images intact
  /// while still resetting the audio pipeline. Used for pause operations
  /// to maintain visual continuity.
  Future<void> stopAndColdReset({bool preserveMetadata = false}) async {
    try {
      LoggerService.info(
          '🎵 StreamRepository: stopAndColdReset started (preserveMetadata: $preserveMetadata)');

      // Store current metadata before any operations if preserving
      StreamMetadata? savedMetadata;
      if (preserveMetadata) {
        savedMetadata = _currentMetadata;
        LoggerService.info(
            '🎵 StreamRepository: Preserving current metadata: ${savedMetadata?.current.showName}');
      }

      // Stop playback and metadata polling
      await _audioHandler.stop();
      _metadataService.stopFetching();

      // CONDITIONAL: Only clear lockscreen if NOT preserving metadata
      if (!preserveMetadata) {
        // Clear native lockscreen (safe no-op on Android)
        try {
          final iosLock = IOSLockscreenService();
          await iosLock.clearLockscreen();
          LoggerService.info(
              '🎵 StreamRepository: Lockscreen cleared (full reset)');
        } catch (_) {}
      } else {
        LoggerService.info(
            '🎵 StreamRepository: Skipping lockscreen clear to preserve metadata');
      }

      // Reset just_audio pipeline to cold-start
      await _audioHandler.resetToColdStart();

      // CONDITIONAL: Reset repository state based on preserve flag
      if (!preserveMetadata) {
        // Full reset - clear everything
        _currentMetadata = null;
        LoggerService.info('🎵 StreamRepository: Full metadata reset');
      } else {
        // Preserve metadata - restore saved metadata
        _currentMetadata = savedMetadata;
        LoggerService.info(
            '🎵 StreamRepository: Metadata preserved and restored');

        // If we have preserved metadata, update the lockscreen with paused state
        if (_currentMetadata != null) {
          _updateMediaMetadata(_currentMetadata!);
        }
      }

      _updateState(StreamState.initial);
      _metadataService.startFetching();

      LoggerService.info(
          '🎵 StreamRepository: stopAndColdReset completed (preserveMetadata: $preserveMetadata)');
    } catch (e) {
      LoggerService.streamError('Error during stopAndColdReset', e);
      _updateState(StreamState.error);
      rethrow;
    }
  }

  // Public streams
  Stream<StreamState> get stateStream => _stateController.stream;
  Stream<StreamMetadata> get metadataStream => _metadataController.stream;

  // Current values
  StreamState get currentState => _currentState;
  StreamMetadata? get currentMetadata => _currentMetadata;

  void _initialize() {
    LoggerService.info(
        '🎵 StreamRepository: Initializing and starting metadata fetch');

    // REMOVED: Force audio reinitialize - let normal initialization work
    // Future.delayed(const Duration(milliseconds: 500), () {
    //   forceAudioReinitialize();
    // });

    // Start fetching metadata immediately
    _metadataService.startFetching();

    // Listen for metadata updates
    _metadataSubscription = _metadataService.metadataStream.listen(
      (metadata) {
        LoggerService.info(
            '🎵 StreamRepository: RECEIVED METADATA: Show=${metadata.current.showName}, Host=${metadata.current.host}');
        _currentMetadata = metadata;
        _metadataController.add(metadata);
        _updateMediaMetadata(metadata);
      },
      onError: (error) {
        LoggerService.streamError('Metadata error', error);
        _updateState(StreamState.error);
      },
    );

    // Listen for playback state changes
    _playbackStateSubscription = _audioHandler.playbackState.listen(
      (playbackState) {
        final isPlaying = playbackState.playing;
        final processingState = playbackState.processingState;

        // Update stream state based on playback state
        switch (processingState) {
          case AudioProcessingState.loading:
            _updateState(StreamState.loading);
            break;
          case AudioProcessingState.buffering:
            _updateState(StreamState.buffering);
            break;
          case AudioProcessingState.ready:
            _updateState(isPlaying ? StreamState.playing : StreamState.paused);
            break;
          case AudioProcessingState.completed:
            _updateState(StreamState.stopped);
            break;
          case AudioProcessingState.idle:
            _updateState(StreamState.initial);
            break;
          case AudioProcessingState.error:
            _updateState(StreamState.error);
            break;
        }

        // REMOVED: Direct lockscreen update on every playback state change
        // This was causing excessive updates (multiple times per second)
        // Now we only update metadata when the actual metadata changes
        // The playback state is still tracked and passed to the native layer
        if (Platform.isIOS && _currentMetadata != null) {
          LoggerService.info('🎵 Playback state changed: playing=$isPlaying');
          // We don't call _updateLockscreenOnPlaybackChange here anymore
        }
      },
    );

    // Initial refresh
    refreshMetadata();
  }

  // REMOVED: _updateLockscreenOnPlaybackChange method
  // This method was causing excessive metadata updates
  // Now we only update metadata when actual metadata changes in _updateMediaMetadata

  Future<void> play({AudioCommandSource? source}) async {
    try {
      LoggerService.info(
          '🎵 StreamRepository: Play requested from ${source ?? 'UI'} - checking server health first');

      // Pre-flight server health check
      try {
        final healthResult = await AudioServerHealthChecker.checkServerHealth(
            StreamConstants.streamUrl);

        if (!healthResult.isHealthy) {
          LoggerService.info(
              '🎵 StreamRepository: Server health check failed: ${healthResult.errorType}');
          await _handleServerError(healthResult);
          return;
        }

        LoggerService.info(
            '🎵 StreamRepository: Server health check passed - proceeding with playback');
      } on NetworkConnectivityException catch (e) {
        LoggerService.info(
            '🎵 StreamRepository: Network connectivity issue during health check: $e');
        // Let the existing network handling take care of this
        // Don't show server error modal for network issues
        _updateState(StreamState.error);
        return;
      }

      _updateState(StreamState.connecting);

      // CRITICAL FIX: Handle lockscreen-initiated commands
      if (source == AudioCommandSource.lockscreen) {
        LoggerService.info(
            '🎵 StreamRepository: Lockscreen-initiated playback detected');
        // UI will be updated through normal playback state listener
      }

      await _audioHandler.play();
      // State will be updated by the playback state listener
    } catch (e) {
      LoggerService.streamError('Error playing stream', e);

      // Try to classify the error
      final errorType = _classifyPlaybackError(e);
      if (errorType != null) {
        final healthResult = AudioServerHealthResult(
          isHealthy: false,
          errorType: errorType,
          message: 'Playback failed: ${e.toString()}',
        );
        await _handleServerError(healthResult);
      } else {
        _updateState(StreamState.error);
      }
      rethrow;
    }
  }

  Future<void> pause({AudioCommandSource? source}) async {
    try {
      LoggerService.info(
          '🎵 StreamRepository: Pause requested - SPOTIFY SIMPLE APPROACH');

      // SPOTIFY SIMPLE: Just stop the audio handler - that's it
      await _audioHandler.stop();
      _updateState(StreamState.initial);

      LoggerService.info(
          '🎵 StreamRepository: Pause completed - simple stop, ready for fresh start');
    } catch (e) {
      LoggerService.streamError('Error pausing stream', e);
      _updateState(StreamState.error);
      rethrow;
    }
  }

  Future<void> stop() async {
    try {
      await _audioHandler.stop();
      _updateState(StreamState.stopped);
      _metadataService.stopFetching();
    } catch (e) {
      LoggerService.streamError('Error stopping stream', e);
      _updateState(StreamState.error);
      rethrow;
    }
  }

  Future<void> retry() async {
    try {
      await stop();
      await Future.delayed(const Duration(seconds: 1));
      await play();
    } catch (e) {
      LoggerService.streamError('Error retrying stream', e);
      _updateState(StreamState.error);
      rethrow;
    }
  }

  void _updateState(StreamState newState) {
    if (_currentState != newState) {
      LoggerService.info('Stream state changed: $_currentState -> $newState');
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  /// Manual refresh of metadata
  Future<void> refreshMetadata() async {
    LoggerService.info(
        '🎵 StreamRepository: MANUAL REFRESH of metadata - Explicitly fetching');
    try {
      final metadata = await _metadataService.fetchMetadataOnce();
      if (metadata != null) {
        LoggerService.info(
            '🎵 METADATA FOUND! Show=${metadata.current.showName}, Host=${metadata.current.host}');
        _currentMetadata = metadata;
        _metadataController.add(metadata);
        _updateMediaMetadata(metadata);
        // REMOVED: Second delayed update that was causing race conditions
      } else {
        LoggerService.debug('🎵 Metadata not yet available');
      }
    } catch (e) {
      LoggerService.streamError('Error refreshing metadata', e);
    }
  }

  /// Restart metadata service after network recovery
  void restartMetadataService() {
    LoggerService.info(
        '🎵 StreamRepository: Restarting metadata service after network recovery');
    _metadataService.startFetching();
    // Also trigger an immediate refresh to get current metadata
    refreshMetadata();
  }

  void _updateMediaMetadata(StreamMetadata metadata) {
    final showInfo = metadata.current;

    // CRITICAL DEBUG: Log exactly what metadata we have
    LoggerService.info(
        '🎵 RAW METADATA: Show="${showInfo.showName}", Host="${showInfo.host}"');
    if (showInfo.hasSongInfo) {
      LoggerService.info(
          '🎵 SONG INFO: Title="${showInfo.songTitle}", Artist="${showInfo.songArtist}"');
    }

    // Get current playback state - we'll need this for the native layer
    final isPlaying = _audioHandler.playbackState.value.playing;

    // Create explicit title and artist fields based on available info
    // CRITICAL: Show name must be the primary title for lockscreen
    final String title = showInfo.showName.isNotEmpty
        ? showInfo.showName
        : 'WBAI Radio'; // Fallback only if empty

    // Artist field will show host info and song if available
    String artist;
    if (showInfo.hasSongInfo &&
        showInfo.songTitle != null &&
        showInfo.songTitle!.isNotEmpty) {
      // If we have song info, include it with the host
      artist = showInfo.songArtist != null && showInfo.songArtist!.isNotEmpty
          ? 'Playing: ${showInfo.songTitle} - ${showInfo.songArtist}'
          : 'Playing: ${showInfo.songTitle}';
    } else {
      // Just show host name
      artist =
          showInfo.host.isNotEmpty ? 'Host: ${showInfo.host}' : 'WBAI 99.5 FM';
    }

    // Create a MediaItem with the show information
    final mediaItem = MediaItem(
      id: 'wbai_live',
      title: title,
      artist: artist,
      album: 'WBAI 99.5 FM',
      displayTitle: title,
      displaySubtitle: artist,
      artUri:
          showInfo.hostImage != null ? Uri.parse(showInfo.hostImage!) : null,
    );

    LoggerService.info(
        '🎵 SENDING TO LOCKSCREEN: Title="$title", Artist="$artist"');

    // ✅ STANDARD FLUTTER APPROACH: Let audio_service handle EVERYTHING!
    // This works for iOS, Android, lifecycle events, artwork caching, etc.
    // No custom Swift code needed - audio_service does it all!

    LoggerService.info(
        '✅ STANDARD: Calling audioHandler.updateMediaItem() - framework will handle lockscreen');
    LoggerService.info(
        '✅ Platform: ${Platform.isAndroid ? 'Android' : 'iOS'}, isPlaying: $isPlaying');
    LoggerService.info('✅ Artwork URL: ${showInfo.hostImage ?? "none"}');

    _audioHandler.updateMediaItem(mediaItem);

    LoggerService.info(
        '✅ STANDARD: MediaItem sent to audio_service - it will handle all platform-specific details');
  }

  /// Handle server-specific errors and reset audio controls
  Future<void> _handleServerError(AudioServerHealthResult healthResult) async {
    LoggerService.info(
        '🎵 StreamRepository: Handling server error: ${healthResult.errorType}');

    // Map server error types to audio states
    GlobalAudioState audioState;
    String errorMessage;

    switch (healthResult.errorType) {
      case AudioServerErrorType.serverUnavailable:
        audioState = GlobalAudioState.serverUnavailable;
        errorMessage = 'Audio server is temporarily unavailable';
        break;
      case AudioServerErrorType.streamNotFound:
        audioState = GlobalAudioState.streamNotFound;
        errorMessage = 'Stream not found on server';
        break;
      case AudioServerErrorType.serverOverloaded:
        audioState = GlobalAudioState.serverUnavailable;
        errorMessage = 'Server is temporarily overloaded';
        break;
      case AudioServerErrorType.connectionTimeout:
        audioState = GlobalAudioState.serverError;
        errorMessage = 'Connection to server timed out';
        break;
      case AudioServerErrorType.authenticationError:
        audioState = GlobalAudioState.serverError;
        errorMessage = 'Access denied by server';
        break;
      case AudioServerErrorType.serverError:
        audioState = GlobalAudioState.serverError;
        errorMessage = 'Server error occurred';
        break;
      case AudioServerErrorType.unknownError:
      case null:
        audioState = GlobalAudioState.serverError;
        errorMessage = healthResult.message ?? 'Unknown server error';
        break;
    }

    // Reset audio controls and clear lockscreen
    await _resetAudioControlsForServerError();

    // Update audio state manager
    AudioStateManager().handleServerError(audioState, errorMessage);

    // Update local stream state
    _updateState(StreamState.error);
  }

  /// Reset audio controls when server errors occur
  /// This ensures play button, lockscreen, and system controls are cleared
  Future<void> _resetAudioControlsForServerError() async {
    try {
      LoggerService.info(
          '🎵 StreamRepository: Resetting audio controls for server error');

      // Stop audio handler and clear controls
      await _audioHandler.stop();

      // Clear iOS lockscreen (safe no-op on Android)
      if (Platform.isIOS) {
        try {
          final iosLock = IOSLockscreenService();
          await iosLock.clearLockscreen();
          LoggerService.info('🎵 StreamRepository: iOS lockscreen cleared');
        } catch (e) {
          LoggerService.error('Error clearing iOS lockscreen: $e');
        }
      }

      // Reset audio handler to cold start state
      await _audioHandler.resetToColdStart();

      LoggerService.info('🎵 StreamRepository: Audio controls reset completed');
    } catch (e) {
      LoggerService.streamError('Error resetting audio controls', e);
    }
  }

  /// Classify playback errors to determine if they're server-related
  AudioServerErrorType? _classifyPlaybackError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('socketexception') ||
        errorString.contains('connection refused')) {
      return AudioServerErrorType.serverUnavailable;
    } else if (errorString.contains('timeout')) {
      return AudioServerErrorType.connectionTimeout;
    } else if (errorString.contains('404') ||
        errorString.contains('not found')) {
      return AudioServerErrorType.streamNotFound;
    } else if (errorString.contains('503') ||
        errorString.contains('service unavailable')) {
      return AudioServerErrorType.serverOverloaded;
    } else if (errorString.contains('401') ||
        errorString.contains('403') ||
        errorString.contains('unauthorized')) {
      return AudioServerErrorType.authenticationError;
    }

    // Return null for non-server errors (network, codec, etc.)
    return null;
  }

  /// Clear server error state and allow retry
  void clearServerError() {
    LoggerService.info('🎵 StreamRepository: Clearing server error state');
    AudioStateManager().clearServerError();
    AudioServerHealthChecker
        .clearCache(); // Clear health check cache for fresh retry
    _updateState(StreamState.initial);
  }

  /// Force complete audio system reinitialize - use when audio is completely broken
  Future<void> forceAudioReinitialize() async {
    try {
      LoggerService.info(
          '🎵 StreamRepository: FORCE AUDIO REINITIALIZE - Complete system reset');

      // Stop everything
      await _audioHandler.stop();
      _metadataService.stopFetching();

      // Force reinitialize audio handler
      await _audioHandler.forceReinitialize();

      // Reset repository state
      _currentMetadata = null;
      _updateState(StreamState.initial);

      // Restart metadata service
      _metadataService.startFetching();

      LoggerService.info(
          '🎵 StreamRepository: Force audio reinitialize complete');
    } catch (e) {
      LoggerService.streamError('Error during force audio reinitialize', e);
      _updateState(StreamState.error);
      rethrow;
    }
  }

  @mustCallSuper
  @mustCallSuper
  void dispose() {
    _metadataSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _stateController.close();
    _metadataController.close();
    _metadataService.dispose();
    // Also dispose the native metadata service to clean up any active timers
    _nativeMetadataService.dispose();
    _audioHandler.customAction('dispose');
  }
}
