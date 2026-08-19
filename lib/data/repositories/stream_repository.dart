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
import '../../core/testing/debug_stream_override.dart';
import '../../domain/models/stream_notice.dart';

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

/// What the presentation layer needs from the audio pipeline.
///
/// [StreamRepository] is the real implementation. This exists so the bloc can
/// be driven by a fake in tests: the real repository builds a just_audio player
/// and audio_service handler in its constructor, which can't run headless — and
/// the questions worth testing ("does an outage raise the modal?", and just as
/// importantly "does normal playback leave it alone?") are all about how the
/// UI reacts to these streams, not about the player itself.
abstract interface class StreamSource {
  Stream<StreamState> get stateStream;
  Stream<StreamMetadata> get metadataStream;
  Stream<StreamNotice?> get noticeStream;

  Future<void> play({AudioCommandSource? source});
  Future<void> pause({AudioCommandSource? source});
  Future<void> stop();
  Future<void> retry();

  /// The listener acknowledged the notice: latch the dismissal and stop the
  /// reconnect loop so it can't immediately re-raise what was just closed.
  void dismissNotice();
}

class StreamRepository implements StreamSource {
  final WBAIAudioHandler _audioHandler;
  final MetadataService _metadataService;
  final NativeMetadataService _nativeMetadataService;
  StreamSubscription? _metadataSubscription;
  StreamSubscription? _playbackStateSubscription;

  final _stateController = StreamController<StreamState>.broadcast();
  final _metadataController = StreamController<StreamMetadata>.broadcast();
  // The ONE channel that tells the UI why audio isn't playing: a StreamNotice
  // when something goes wrong, null when it's cleared. A confirmed server
  // outage emits kind `outage`; anything we couldn't pin on the server (network
  // blip, captive-portal TLS interception, reconnect exhausted against a server
  // that probes healthy) emits kind `connection`. Both render through the same
  // modal — there is no second, quieter surface. Before this was unified, the
  // `connection` paths set the error state and emitted nothing at all, so the
  // listener got a spinner that stopped and no explanation whatsoever.
  final _noticeController = StreamController<StreamNotice?>.broadcast();

  StreamState _currentState = StreamState.initial;
  StreamMetadata? _currentMetadata;

  // PHASE 5: connecting watchdog. Playback starts immediately (no blocking
  // pre-flight), but if it never reaches `playing` within this window we probe
  // the server: if it's down, surface the error modal and halt reconnects;
  // if it's healthy, keep waiting (slow connection, not a dead server).
  Timer? _connectingWatchdog;
  static const Duration _connectingTimeout = Duration(seconds: 8);

  // PHASE 10: guard against re-entrancy while classifying a player error.
  bool _handlingPlayerError = false;

  // Dismiss latch: once the user taps "Got it" on the server-error modal, we
  // stop re-surfacing the SAME outage (the reconnect loop / player-error path
  // would otherwise re-emit and the modal would pop straight back, looking
  // undismissable). Reset on the next explicit play() so a new attempt can
  // surface a fresh outage.
  bool _noticeDismissed = false;

  /// Push a notice (or null to clear) to the UI. Guards against emitting after
  /// dispose, which the reconnect/watchdog timers can otherwise still attempt.
  void _emitNotice(StreamNotice? notice) {
    if (_noticeController.isClosed) return;
    _noticeController.add(notice);
  }

  /// Surface a playback failure we could NOT pin on the server: move to the
  /// error state, then raise the `connection` notice. Honours the same dismiss
  /// latch as an outage, so a notice the user just closed can't pop straight
  /// back from a late-arriving error on the same failed attempt.
  void _emitConnectionNotice(String reason) {
    LoggerService.warning('🎵 StreamRepository: Connection notice ($reason)');
    _updateState(StreamState.error);
    if (_noticeDismissed) {
      LoggerService.info(
          '🎵 StreamRepository: Connection notice suppressed (user dismissed)');
      return;
    }
    _emitNotice(const StreamNotice.connection());
  }

  // True between a play() request and the player actually reaching `playing`.
  // During this window the source can momentarily report `ready` before its
  // `playing` flag flips true; without this guard that instant is mapped to
  // `paused`, which flashes the play icon between the spinner and the pause
  // icon. While awaiting play we keep it a spinner (buffering) state instead.
  bool _awaitingPlay = false;

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
      _awaitingPlay = false;
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

      // We're back to a clean, playable state, so any notice describing the
      // old fault is stale. Network recovery routes through here, which means
      // a "can't reach the stream" modal raised while offline (and hidden
      // behind NetworkLostAlert) clears itself instead of being revealed as a
      // stale modal the moment the connection returns. NOT a user dismissal,
      // so the _noticeDismissed latch is deliberately left alone.
      _emitNotice(null);
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
  @override
  Stream<StreamState> get stateStream => _stateController.stream;
  @override
  Stream<StreamMetadata> get metadataStream => _metadataController.stream;
  @override
  Stream<StreamNotice?> get noticeStream => _noticeController.stream;

  // Current values
  StreamState get currentState => _currentState;
  StreamMetadata? get currentMetadata => _currentMetadata;

  void _initialize() {
    // Start fetching metadata immediately
    _metadataService.startFetching();

    // Listen for metadata updates
    _metadataSubscription = _metadataService.metadataStream.listen(
      (metadata) {
        _currentMetadata = metadata;
        _metadataController.add(metadata);
        _updateMediaMetadata(metadata);
      },
      onError: (error) {
        // Log only. A failed *metadata* poll says nothing about playback —
        // audio is very often still streaming fine. Flipping playback state to
        // `error` here made a transient show-info fetch failure knock the play
        // button out of its playing state mid-stream.
        LoggerService.streamError('Metadata error (playback unaffected)', error);
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
            if (isPlaying) {
              _awaitingPlay = false;
              _updateState(StreamState.playing);
            } else if (_awaitingPlay) {
              // Startup blip: the source is ready but the player's `playing`
              // flag hasn't flipped true yet. Stay on a spinner (buffering)
              // state so the play icon never flashes between the spinner and
              // the pause icon — we only reach `playing` next.
              _updateState(StreamState.buffering);
            } else {
              _updateState(StreamState.paused);
            }
            break;
          case AudioProcessingState.completed:
            // A 24/7 live stream HAS NO END, so `completed` is ALWAYS a
            // failure — never a clean stop.
            //
            // This used to map to StreamState.stopped, i.e. treated exactly
            // like the user pressing stop: watchdog cancelled, _awaitingPlay
            // cleared, NO notice raised. That is why the "plays the cache then
            // STOPS" bug was completely silent to the listener. The handler is
            // already reconnecting; route through the error classifier so that
            // if the reconnect chain exhausts, the listener actually gets told.
            // See docs/audio-play-bug.md.
            LoggerService.warning(
                '🎵 StreamRepository: LIVE stream reported completed - treating as failure, not a stop');
            _onPlayerError();
            break;
          case AudioProcessingState.idle:
            // Guard: on Android, setAudioSource briefly emits idle before
            // loading begins. Without this check that blip flashes the play
            // button while the spinner is still expected. iOS is unaffected —
            // it uses resume-in-place and never hits setAudioSource mid-play.
            if (!_awaitingPlay) {
              _updateState(StreamState.initial);
            }
            break;
          case AudioProcessingState.error:
            // PHASE 10: the handler emits this after its bounded reconnect is
            // exhausted (e.g. a mid-stream Icecast drop). Classify it so a real
            // server outage surfaces the modal, not just a generic error.
            _onPlayerError();
            break;
        }

        // Playback state tracked; metadata is updated separately in _updateMediaMetadata.
      },
    );

    // Initial refresh
    refreshMetadata();
  }

  // REMOVED: _updateLockscreenOnPlaybackChange method
  // This method was causing excessive metadata updates
  // Now we only update metadata when actual metadata changes in _updateMediaMetadata

  @override
  Future<void> play({AudioCommandSource? source}) async {
    try {
      LoggerService.info(
          '🎵 StreamRepository: Play requested from ${source ?? 'UI'} - starting immediately');

      // PHASE 2: No blocking pre-flight health check. Reflect activity in the
      // UI immediately and let the player connect. The old pre-flight GET added
      // ~2s of fixed latency in front of every play; just_audio surfaces real
      // connection/stream errors which we classify on the failure path below.
      // A fresh, explicit play attempt clears the dismiss latch so a genuinely
      // new outage can surface the modal again.
      _noticeDismissed = false;
      _awaitingPlay = true;
      _updateState(StreamState.connecting);

      // PHASE 5: arm the watchdog in case the connection silently stalls (the
      // audio handler swallows connect failures into a background reconnect
      // loop, so they never throw here).
      _startConnectingWatchdog();

      await _audioHandler.play();
      // State will be updated by the playback state listener
    } catch (e) {
      LoggerService.streamError('Error playing stream', e);
      _cancelConnectingWatchdog();
      await _handlePlaybackFailure(e);
      rethrow;
    }
  }

  /// Classify and surface a playback failure. Tries to classify directly from
  /// the thrown error first; if that's inconclusive, consults the health
  /// checker to distinguish a server outage from a generic error — but only on
  /// the failure path, so the happy path carries no pre-flight latency.
  Future<void> _handlePlaybackFailure(Object e) async {
    final directType = _classifyPlaybackError(e);
    if (directType != null) {
      await _handleServerError(AudioServerHealthResult(
        isHealthy: false,
        errorType: directType,
        message: 'Playback failed: $e',
      ));
      return;
    }

    try {
      final health = await AudioServerHealthChecker.checkServerHealth(
          DebugStreamOverride.effectiveUrl);
      if (!health.isHealthy) {
        await _handleServerError(health);
        return;
      }
    } on NetworkConnectivityException catch (ne) {
      // Network issue, not a server issue — falls through to the retryable
      // notice below rather than the outage modal.
      LoggerService.info(
          '🎵 StreamRepository: Network connectivity issue during failure classification: $ne');
    }

    _emitConnectionNotice('playback failure, server not confirmed down');
  }

  /// PHASE 5: Arm a watchdog that fires if playback hasn't reached `playing`
  /// within [_connectingTimeout]. On a healthy-but-slow server it does nothing;
  /// on a down server it shows the error modal and halts the reconnect loop.
  void _startConnectingWatchdog() {
    _connectingWatchdog?.cancel();
    _connectingWatchdog = Timer(_connectingTimeout, _onConnectingTimeout);
  }

  void _cancelConnectingWatchdog() {
    _connectingWatchdog?.cancel();
    _connectingWatchdog = null;
  }

  Future<void> _onConnectingTimeout() async {
    if (_currentState == StreamState.playing) return;

    LoggerService.warning(
        '🎵 StreamRepository: Connecting watchdog fired (state=$_currentState) - probing server health');
    try {
      final health = await AudioServerHealthChecker.checkServerHealth(
          DebugStreamOverride.effectiveUrl);
      if (!health.isHealthy) {
        LoggerService.info(
            '🎵 StreamRepository: Watchdog confirmed server down (${health.errorType}) - showing modal, halting reconnect');
        _audioHandler.haltReconnect();
        await _handleServerError(health);
      } else {
        LoggerService.info(
            '🎵 StreamRepository: Watchdog - server healthy, continuing to wait for connection');
      }
    } on NetworkConnectivityException catch (ne) {
      // Network issue, not a server issue — the retryable notice, not the
      // outage one. Previously this set the error state and said nothing, so
      // the spinner just stopped with no explanation.
      LoggerService.info(
          '🎵 StreamRepository: Watchdog network connectivity issue: $ne');
      _audioHandler.haltReconnect();
      _emitConnectionNotice('watchdog network connectivity issue');
    }
  }

  /// PHASE 10: Classify a player error (reconnect exhausted) and surface it: a
  /// real server outage shows the modal; anything else stays a generic error.
  Future<void> _onPlayerError() async {
    if (_handlingPlayerError) return;
    _handlingPlayerError = true;
    try {
      _cancelConnectingWatchdog();
      _updateState(StreamState.error);
      LoggerService.warning(
          '🎵 StreamRepository: Player error - probing server to classify');
      final health = await AudioServerHealthChecker.checkServerHealth(
          DebugStreamOverride.effectiveUrl);
      if (!health.isHealthy) {
        await _handleServerError(health);
      } else {
        // Reconnect exhausted, yet the server probes fine — something between
        // us and it (or the player itself) is at fault. Still a dead end for
        // the listener, so it gets the retryable notice rather than silence.
        _emitConnectionNotice('reconnect exhausted, server probes healthy');
      }
    } on NetworkConnectivityException catch (ne) {
      // Network issue, not a server issue — retryable notice, not the outage
      // modal (the station may well be fine).
      LoggerService.info(
          '🎵 StreamRepository: Player error during network issue: $ne');
      _emitConnectionNotice('network issue while classifying player error');
    } catch (e) {
      LoggerService.streamError('Error classifying player error', e);
      _emitConnectionNotice('unclassifiable player error');
    } finally {
      _handlingPlayerError = false;
    }
  }

  @override
  Future<void> pause({AudioCommandSource? source}) async {
    try {
      // A deliberate pause ends any in-flight play attempt, so a subsequent
      // `ready` event should map to `paused` normally again.
      _awaitingPlay = false;

      // Use pause() instead of stop() to keep the audio session active and
      // preserve Now Playing status on iOS. stop() was nuking mediaItem and
      // deactivating the session, which let another app's metadata flash on
      // the lock screen during the subsequent play→reconnect gap.
      await _audioHandler.pause();
      _updateState(StreamState.paused);
    } catch (e) {
      LoggerService.streamError('Error pausing stream', e);
      _updateState(StreamState.error);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    try {
      _awaitingPlay = false;
      await _audioHandler.stop();
      _updateState(StreamState.stopped);
      _metadataService.stopFetching();
    } catch (e) {
      LoggerService.streamError('Error stopping stream', e);
      _updateState(StreamState.error);
      rethrow;
    }
  }

  @override
  Future<void> retry() async {
    try {
      await stop();
      await Future.delayed(const Duration(seconds: 1));
      // stop() halts metadata polling and play() does not restart it, so
      // without this a retry leaves the show name/host frozen at whatever was
      // last fetched. Now that "Try again" is a button on the notice modal
      // this path is a normal thing for a listener to hit, not a rarity.
      restartMetadataService();
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

      // PHASE 5: once playback settles, the connecting watchdog is done.
      if (newState == StreamState.playing ||
          newState == StreamState.paused ||
          newState == StreamState.stopped ||
          newState == StreamState.error ||
          newState == StreamState.initial) {
        _cancelConnectingWatchdog();
      }

      // A play attempt is over once we actually start playing or it fails
      // outright. (Deliberately NOT cleared on `initial`, which the iOS source
      // rebuild churns through mid-play.)
      if (newState == StreamState.playing ||
          newState == StreamState.stopped ||
          newState == StreamState.error) {
        _awaitingPlay = false;
      }
    }
  }

  /// Manual refresh of metadata
  Future<void> refreshMetadata() async {
    try {
      // fetchMetadataOnce() emits to metadataStream → subscription listener
      // handles _currentMetadata, _metadataController, and _updateMediaMetadata.
      await _metadataService.fetchMetadataOnce();
    } catch (e) {
      LoggerService.streamError('Error refreshing metadata', e);
    }
  }

  /// Restart metadata service after network recovery
  void restartMetadataService() {
    _metadataService.startFetching();
    // Also trigger an immediate refresh to get current metadata
    refreshMetadata();
  }

  Future<void> _updateMediaMetadata(StreamMetadata metadata) async {
    final showInfo = metadata.current;

    final String title = showInfo.showName.isNotEmpty
        ? showInfo.showName
        : 'WBAI Radio';

    String artist;
    if (showInfo.hasSongInfo &&
        showInfo.songTitle != null &&
        showInfo.songTitle!.isNotEmpty) {
      artist = showInfo.songArtist != null && showInfo.songArtist!.isNotEmpty
          ? 'Playing: ${showInfo.songTitle} - ${showInfo.songArtist}'
          : 'Playing: ${showInfo.songTitle}';
    } else {
      artist =
          showInfo.host.isNotEmpty ? 'Host: ${showInfo.host}' : 'WBAI 99.5 FM';
    }

    LoggerService.info('Metadata: show="$title" artist="$artist"');

    final artUri = await _resolveArtUri(
      showInfo.hostImage,
      metadata.stationFallbackImage,
    );

    final mediaItem = MediaItem(
      id: 'wbai_live',
      title: title,
      artist: artist,
      album: 'WBAI 99.5 FM',
      displayTitle: title,
      displaySubtitle: artist,
      artUri: artUri,
    );

    _audioHandler.updateMediaItem(mediaItem);
  }

  /// Returns the show image URI if reachable, otherwise the station fallback.
  Future<Uri?> _resolveArtUri(String? showImage, String? fallback) async {
    if (showImage != null && showImage.isNotEmpty) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final request = await client.headUrl(Uri.parse(showImage));
        final response = await request.close();
        await response.drain<void>();
        client.close();
        if (response.statusCode == 200) return Uri.parse(showImage);
      } catch (_) {}
    }
    return fallback != null ? Uri.parse(fallback) : null;
  }

  /// Handle server-specific errors and reset audio controls
  Future<void> _handleServerError(AudioServerHealthResult healthResult) async {
    // If the user already dismissed this outage, don't resurrect the modal.
    // A fresh play() clears the latch and lets a new outage surface.
    if (_noticeDismissed) {
      LoggerService.info(
          '🎵 StreamRepository: Server error suppressed (user dismissed) - not re-showing modal');
      return;
    }

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

    // A confirmed outage must reach the listener immediately. Player cleanup
    // can block for more than a minute while AVPlayer unwinds a timed-out
    // source, so it must never gate the notice.
    _audioHandler.haltReconnect();
    AudioStateManager().handleServerError(audioState, errorMessage);
    _updateState(StreamState.error);
    _emitNotice(StreamNotice.outage(detail: errorMessage));

    // The listener has been informed. Clear platform controls afterward.
    await _resetAudioControlsForServerError();
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

      // Do not call resetToColdStart() here: it resolves and loads the endpoint
      // we just proved is broken. stop() leaves the player idle, and the next
      // explicit Play already rebuilds a fresh source.
      LoggerService.info('🎵 StreamRepository: Audio controls cleared');
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
  @override
  void dismissNotice() {
    LoggerService.info('🎵 StreamRepository: Clearing server error state');
    // Latch the dismissal and stop the background reconnect loop so it can't
    // keep hammering the dead server and re-raise the modal we just closed.
    _noticeDismissed = true;
    _audioHandler.haltReconnect();
    AudioStateManager().clearServerError();
    AudioServerHealthChecker
        .clearCache(); // Clear health check cache for fresh retry
    _emitNotice(null); // Hide the notice modal
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
    _cancelConnectingWatchdog();
    _metadataSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _stateController.close();
    _metadataController.close();
    _noticeController.close();
    _metadataService.dispose();
    // Also dispose the native metadata service to clean up any active timers
    _nativeMetadataService.dispose();
    _audioHandler.customAction('dispose');
  }
}
