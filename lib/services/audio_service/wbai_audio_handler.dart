import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/stream_constants.dart';
import '../../core/services/logger_service.dart';
import '../../core/utils/m3u_parser.dart';
import '../../data/models/stream_metadata.dart';
import '../samsung_media_session_service.dart';

/// Handles all audio-related operations including background playback
/// Modified to use a permanent dummy MediaItem to prevent just_audio_background
/// from controlling the iOS lockscreen metadata
class WBAIAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player;
  final String _streamUrl;
  StreamMetadata? _currentMetadata;

  // Optional: track last buffering log time to reduce log noise
  DateTime? _lastBufferingUpdate;

  // SINGLE SOURCE OF TRUTH: One MediaItem field (like working Pacifica app)
  MediaItem? _currentMediaItem;

  // ANDROID: throttle diagnostic logs
  DateTime? _lastAndroidDiag;

  WBAIAudioHandler._(
    this._player,
    this._streamUrl,
  ) {
    // CRITICAL: Set initial MediaItem immediately (working pattern)
    _setInitialMediaItem();
    _init();
  }

  /// WORKING PATTERN: Set initial MediaItem immediately (from Pacifica app)
  void _setInitialMediaItem() {
    _currentMediaItem = MediaItem(
      id: "wbai_live",
      album: "Live Radio",
      title: "WBAI 99.5 FM",
      artist: "Pacifica Radio",
      duration: const Duration(hours: 24),
      // REMOVED: Broken placeholder artwork that was causing 404 errors and overriding real artwork
      // artUri: Uri.parse("https://www.wbai.org/playlist/images/wbai_logo.png"),
    );

    // DELAY: Don't show generic player immediately - wait for real metadata
    // mediaItem.add(_currentMediaItem); // ← REMOVED: Causes generic player flash
    LoggerService.info(
        '🔍 INITIAL LOAD FIX: _setInitialMediaItem() called but NOT showing generic player');
    LoggerService.info(
        '🎯 INITIAL LOAD FIX: Waiting for real metadata before showing player');
  }

  static Future<WBAIAudioHandler> create() async {
    final player = AudioPlayer();

    LoggerService.info(
        '🎵 Initializing audio handler (single source of truth)');

    return WBAIAudioHandler._(
      player,
      StreamConstants.streamUrl,
    );
  }

  Future<void> _init() async {
    try {
      LoggerService.info(
          '🎵 AudioHandler: Initializing with EXPERT M3U parsing');

      // Configure audio session category - do NOT activate until user presses play
      // Activating at startup causes iOS paramErr (-50) before foreground audio is allowed
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      LoggerService.info(
          '🎯 SAMSUNG FIX: Audio session configured for lockscreen controls');

      // EXPERT SOLUTION: Parse M3U playlist to get direct stream URL
      final directStreamUrl = await _resolveStreamUrl(_streamUrl);
      LoggerService.info(
          '🎵 AudioHandler: Resolved stream URL: $directStreamUrl');

      // Configure audio source with direct stream URL (industry standard)
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(directStreamUrl),
          // Android uses a real tag so just_audio_background can render notifications
          // iOS keeps using the dummy item to defer lockscreen to Swift
          tag: _currentMediaItem,
        ),
      );
      if (Platform.isAndroid) {
        // Removed: _lastAndroidTagApplied tracking (simplified)
        _debugDumpAndroidState('init:setAudioSource');
      }

      // Only update playback state, not metadata
      // Our Swift implementation will handle the lockscreen metadata
      Future.delayed(const Duration(milliseconds: 500), () {
        _updatePlaybackStateOnly();
      });

      // Set up event listeners
      _player.processingStateStream.listen(_handleProcessingState);

      // WORKING PATTERN: Connect event streams like Pacifica app
      _player.playbackEventStream.listen(_broadcastState);
      _player.playerStateStream.listen(_handlePlayerState);

      // ANDROID: deep diagnostics - observe handler streams
      if (Platform.isAndroid) {
        mediaItem.listen((item) {
          final t = item?.title ?? '';
          final a = item?.artist ?? '';
          LoggerService.info(
              '🤖 ANDROID DIAG: mediaItem changed -> title="$t" artist="$a"');
        });
        playbackState.listen((state) {
          // throttle
          final now = DateTime.now();
          if (_lastAndroidDiag == null ||
              now.difference(_lastAndroidDiag!) > const Duration(seconds: 2)) {
            _lastAndroidDiag = now;
            _debugDumpAndroidState('listener:playbackState');
          }
        });
      }
    } catch (e) {
      LoggerService.audioError('Error initializing audio handler', e);
      _handleError(e);
    }
  }

  // CRITICAL: EXACT working pattern from Pacifica app (SINGLE SOURCE OF TRUTH)
  void _broadcastState([PlaybackEvent? event]) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop, // X button to close player completely
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop, // Add stop action for X button
      },
      androidCompactActionIndices: const [0, 1],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: 0,
    ));

    // PACIFICA PATTERN: Simple MediaItem management (SINGLE SOURCE OF TRUTH)
    // Only show player when we have real metadata or when actively playing
    final shouldShowPlayer = _player.processingState != ProcessingState.idle &&
        _currentMediaItem != null &&
        (_currentMediaItem!.title != "WBAI 99.5 FM" || _player.playing);

    mediaItem.add(shouldShowPlayer ? _currentMediaItem : null);

  }

  void _handlePlayerState(PlayerState state) {
    if (state.playing && _currentMetadata != null) {
      _updateMediaItem(
        _currentMetadata!.currentSong,
        _currentMetadata!.artist,
      );
    }

    // REMOVED: Competing MediaItem.add() call that was causing oscillation
    // Let the real metadata system be the ONLY source of MediaItem updates
    // This was the root cause of the 500ms oscillation pattern

    // Handle errors through PlayerState
    if (!state.playing &&
        _player.processingState == ProcessingState.completed) {
      LoggerService.audioError('Playback ended unexpectedly');
      _handleError('Stream playback ended unexpectedly');
    }
  }

  void _handleProcessingState(ProcessingState state) {
    // Track streaming state for intelligent metadata updates
    switch (state) {
      case ProcessingState.idle:
        LoggerService.info('🎵 AUDIO STATE: Idle');
        break;
      case ProcessingState.loading:
        LoggerService.info('🎵 AUDIO STATE: Loading');
        break;
      case ProcessingState.buffering:
        // Limit buffering log frequency to avoid spam
        final now = DateTime.now();
        if (_lastBufferingUpdate == null ||
            now.difference(_lastBufferingUpdate!) >
                const Duration(seconds: 5)) {
          LoggerService.info('🎵 AUDIO STATE: Buffering');
          _lastBufferingUpdate = now;
        }
        break;
      case ProcessingState.ready:
        LoggerService.info('🎵 AUDIO STATE: Ready (actively streaming)');
        break;
      case ProcessingState.completed:
        LoggerService.info('🎵 AUDIO STATE: Completed');
        break;
    }
  }

  void _handleError(dynamic error) {
    LoggerService.audioError('Audio error', error);
  }

  Future<void> _reconnect() async {
    try {
      LoggerService.info('🎵 Attempting to reconnect to stream...');

      // EXPERT: Reset with resolved direct stream URL
      await _player.pause();
      await _player.seek(Duration.zero);
      final directStreamUrl = await _resolveStreamUrl(_streamUrl);
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(directStreamUrl),
          tag: _currentMediaItem, // Use current MediaItem
        ),
      );

      // Resume playback
      await _player.play();
      LoggerService.info('🎵 Reconnection successful');
    } catch (e) {
      LoggerService.audioError('Error during reconnection', e);
      _handleError(e);

      // Schedule another reconnect attempt
      Future.delayed(const Duration(seconds: 5), () {
        if (!_player.playing) {
          _reconnect();
        }
      });
    }
  }

  @override
  Future<void> play() async {
    try {
      LoggerService.info('🎯 ONE TRUTH: Play button pressed - starting flow');

      // CRITICAL: Request audio focus before playing (Samsung requirement)
      final session = await AudioSession.instance;
      final success = await session.setActive(true);
      if (!success) {
        LoggerService.warning(
            '🎯 SAMSUNG FIX: Failed to gain audio focus - lockscreen controls may not work, but continuing playback');
      } else {
        LoggerService.info(
            '🎯 SAMSUNG FIX: Audio focus gained successfully - lockscreen controls should now work');
      }

      // CACHE FIX: ALWAYS set fresh AudioSource - never trust existing one
      // This ensures every play button press behaves like app startup (fresh stream)
      LoggerService.info(
          '🎯 CACHE FIX: ALWAYS setting fresh AudioSource (no cache check)');
      final directStreamUrl = await _resolveStreamUrl(_streamUrl);
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(directStreamUrl),
          tag: _currentMediaItem,
        ),
      );
      LoggerService.info(
          '🎯 CACHE FIX: Fresh AudioSource set - guaranteed no cached audio');

      LoggerService.info(
          '🎯 ONE TRUTH: Calling _player.play() - event listener will trigger _broadcastState');
      await _player.play();

      // REMOVED: Manual _broadcastState call - this was causing oscillation
      // The event listener will handle state broadcasting automatically

      // CRITICAL: Use our dummy MediaItem to update playback state only
      // Our Swift implementation will handle the lockscreen metadata
      _updateMediaSession(_player.playing, _currentMediaItem!);

      // CRITICAL: Update Samsung MediaSession playback state
      // This is the native Android MediaSession that Samsung J7 requires
      await SamsungMediaSessionService.updatePlaybackState(true);

      // DELAY FIX: Wait for current metadata before showing Samsung notification
      if (_currentMetadata != null) {
        LoggerService.info(
            '🔍 METADATA DELAY FIX: Using existing metadata for Samsung notification');
        await SamsungMediaSessionService.updateMetadata(
          _currentMetadata!.currentSong,
          _currentMetadata!.artist,
        );
      } else {
        LoggerService.info(
            '🔍 METADATA DELAY FIX: No metadata available yet - Samsung will show static until metadata arrives');
      }

      // STANDARD BEHAVIOR: Show notification only when PLAYING starts
      await SamsungMediaSessionService.showNotification();
      LoggerService.info(
          '🔍 SAMSUNG DEBUG: Notification shown because PLAY was pressed (STANDARD)');

      if (Platform.isAndroid) {
        _debugDumpAndroidState('play:afterUpdateSession');
      }
    } catch (e) {
      LoggerService.audioError('Error playing stream', e);
      _handleError(e);
      _reconnect();
    }
  }

  @override
  Future<void> pause() async {
    try {
      LoggerService.info('🎵 AudioHandler: Pause requested');
      await _player.pause();

      // REMOVED: Manual _broadcastState call - this was causing oscillation
      // The event listener will handle state broadcasting automatically

      // CRITICAL: Release audio focus when pausing (Samsung requirement)
      final session = await AudioSession.instance;
      await session.setActive(false);
      LoggerService.info('🎯 SAMSUNG FIX: Audio focus released on pause');

      // CRITICAL: Use our dummy MediaItem to update playback state only
      // Our Swift implementation will handle the lockscreen metadata
      _updateMediaSession(_player.playing, _currentMediaItem!);

      // CRITICAL: Update Samsung MediaSession playback state
      // This is the native Android MediaSession that Samsung J7 requires
      await SamsungMediaSessionService.updatePlaybackState(false);

      // STANDARD BEHAVIOR: Hide notification when PAUSED (like other apps)
      await SamsungMediaSessionService.hideNotification();
      LoggerService.info(
          '🔍 SAMSUNG DEBUG: Notification hidden because PAUSE was pressed (STANDARD)');
    } catch (e) {
      LoggerService.audioError('Error pausing stream', e);
      _handleError(e);
    }
  }

  @override
  Future<void> stop() async {
    try {
      LoggerService.info(
          '🎵 AudioHandler: Stop requested - REMOVING player from notification tray');

      // CRITICAL: Complete reset like app startup - clear AudioSource
      await _player.stop();
      LoggerService.info(
          '🎯 REAL FIX: AudioPlayer.stop() called - clears all cached audio data');

      // Release audio focus completely
      final session = await AudioSession.instance;
      await session.setActive(false);
      LoggerService.info('🎯 SAMSUNG FIX: Audio focus released on stop');

      // Hide Samsung notification completely
      await SamsungMediaSessionService.hideNotification();
      LoggerService.info(
          '🔍 SAMSUNG DEBUG: Notification hidden because STOP was pressed');

      // Set playback state to idle and clear MediaItem to remove from tray
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));

      // Clear MediaItem to remove player from notification tray completely
      mediaItem.add(null);
      LoggerService.info(
          '🎯 STOP: Player removed from notification tray - MediaItem set to null');

      // CRITICAL: Use proper AudioHandler approach - set to stopped state
      // This signals the AudioService to remove the foreground notification
      playbackState.add(PlaybackState(
        controls: [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 0.0,
      ));
      LoggerService.info(
          '🎯 STOP: Set playback state to idle with no controls to remove service');
    } catch (e) {
      LoggerService.audioError('Error stopping and removing player', e);
      _handleError(e);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    // Seeking not supported in live streams
    LoggerService.info(
        '🎵 AudioHandler: Seek requested but not supported for live streams');
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      await _player.dispose();
    }
  }

  /// Updates the media session state without updating the MediaItem
  /// This ensures just_audio_background won't control the lockscreen
  Future<void> _updateMediaSession(bool playing, MediaItem mediaItem) async {
    LoggerService.info('🎵 AudioHandler: Updating media session state only');

    final controls = [
      MediaControl.stop,
      playing ? MediaControl.pause : MediaControl.play,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1],
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );

    // CRITICAL FIX: Do NOT update the mediaItem stream
    // This prevents just_audio_background from controlling the lockscreen
    // Our Swift implementation is the single source of truth for metadata
    // this.mediaItem.add(mediaItem); // Intentionally commented out

    LoggerService.info(
        '🎵 AudioHandler: Updated playback state only, not metadata');
  }

  /// Updates the current MediaItem with real metadata (SINGLE SOURCE OF TRUTH)
  Future<void> _updateMediaItem(String title, String artist) async {
    LoggerService.info(
        '🎵 AudioHandler: Received metadata update: "$title" by "$artist"');

    // Skip empty or placeholder updates
    if (title.isEmpty ||
        title == 'Loading stream...' ||
        title == 'Connecting...') {
      LoggerService.info('🎵 AudioHandler: Skipping empty/placeholder update');
      return;
    }

    // PACIFICA PATTERN: Update _currentMediaItem with real metadata
    _currentMediaItem = MediaItem(
      id: "wbai_live",
      album: "WBAI 99.5 FM",
      title: title,
      artist: artist,
      duration: const Duration(hours: 24),
      // REMOVED: Broken placeholder artwork that was causing 404 errors and overriding real artwork
      // artUri: Uri.parse("https://www.wbai.org/playlist/images/wbai_logo.png"),
    );

    // Let _broadcastState handle the mediaItem.add() call (SINGLE SOURCE OF TRUTH)
    LoggerService.info(
        '🔍 METADATA BATTLE: _updateMediaItem() called with REAL metadata: "$title" by "$artist"');
    LoggerService.info(
        '🎯 ONE TRUTH: Updated _currentMediaItem with real metadata: "$title" by "$artist"');
    LoggerService.info(
        '🎯 ONE TRUTH: Next _broadcastState call will use this updated MediaItem');

    // CRITICAL: Update Samsung MediaSession with real metadata
    LoggerService.info(
        '🔍 SAMSUNG DEBUG: Calling SamsungMediaSessionService.updateMetadata("$title", "$artist")');
    await SamsungMediaSessionService.updateMetadata(title, artist);
    LoggerService.info(
        '🔍 SAMSUNG DEBUG: SamsungMediaSessionService.updateMetadata() completed');
  }

  /// Updates only the playback state without changing metadata
  /// This prevents iOS from caching placeholder values
  Future<void> _updatePlaybackStateOnly() async {
    LoggerService.info('🎵 AudioHandler: Updating playback state only');

    // Force a playback state update
    playbackState.add(
      playbackState.value.copyWith(
        playing: _player.playing,
        processingState: playbackState.value.processingState,
        updatePosition: _player.position,
        speed: _player.speed,
      ),
    );

    LoggerService.info(
        '🎵 AudioHandler: Playback state updated, using Swift for lockscreen metadata');
  }

  /// Public: Reset the audio pipeline to a cold-start idle state
  /// - Stops playback
  /// - Re-sets the audio source with the permanent dummy MediaItem
  /// - Clears internal flags and cached metadata
  /// - Updates playback state to idle/ready as appropriate without starting playback
  Future<void> resetToColdStart() async {
    try {
      LoggerService.info('🎵 AudioHandler: Reset to cold-start requested');
      await _player.pause();
      await _player.seek(Duration.zero);

      // EXPERT: Use resolved direct stream URL
      final directStreamUrl = await _resolveStreamUrl(_streamUrl);
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(directStreamUrl),
          tag: _currentMediaItem,
        ),
      );
      _currentMetadata = null;

      // Force update of playback state to reflect idle
      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
        ),
      );

      LoggerService.info('🎵 AudioHandler: Cold-start reset complete');
    } catch (e) {
      LoggerService.audioError('Error during cold-start reset', e);
      _handleError(e);
    }
  }

  /// Complete audio system reset - reinitializes everything from scratch
  Future<void> forceReinitialize() async {
    try {
      LoggerService.info(
          '🎵 AudioHandler: FORCE REINITIALIZE - Complete reset');

      // Stop and dispose current player state
      await _player.pause();
      await _player.seek(Duration.zero);

      // EXPERT: Reinitialize with resolved direct stream URL
      final directStreamUrl = await _resolveStreamUrl(_streamUrl);
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(directStreamUrl),
          tag: _currentMediaItem,
        ),
      );

      // Reset all internal state
      _currentMetadata = null;
      _lastBufferingUpdate = null;

      // Force clean playback state
      playbackState.add(
        PlaybackState(
          controls: [MediaControl.play],
          systemActions: const {
            MediaAction.play,
            MediaAction.pause,
            MediaAction.stop
          },
          androidCompactActionIndices: const [0],
          processingState: AudioProcessingState.idle,
          playing: false,
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
          speed: 1.0,
        ),
      );

      LoggerService.info(
          '🎵 AudioHandler: Force reinitialize complete - ready for playback');
    } catch (e) {
      LoggerService.audioError('Error during force reinitialize', e);
      _handleError(e);
    }
  }

  /// EXPERT METHOD: Resolve M3U playlist to direct stream URL
  Future<String> _resolveStreamUrl(String url) async {
    try {
      // If it's already a direct stream URL, use it as-is
      if (!url.endsWith('.m3u')) {
        return url;
      }

      LoggerService.info('🎵 AudioHandler: Fetching M3U playlist from: $url');

      // Fetch M3U playlist content
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch M3U playlist: ${response.statusCode}');
      }

      // Parse M3U to extract direct stream URL
      final directUrl = M3UParser.parseStreamUrl(response.body);
      if (directUrl == null) {
        throw Exception('No stream URL found in M3U playlist');
      }

      LoggerService.info(
          '🎵 AudioHandler: Extracted direct stream URL: $directUrl');
      return directUrl;
    } catch (e) {
      LoggerService.audioError('Error resolving stream URL', e);
      // Fallback to original URL
      return url;
    }
  }

  /// Updates metadata from stream metadata
  void updateMetadata(StreamMetadata metadata) {
    LoggerService.info(
        '🎵 AudioHandler: Updating with LIVE metadata: ${metadata.currentSong}');
    _currentMetadata = metadata;
    _updateMediaItem(
      metadata.currentSong,
      metadata.artist,
    );
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    LoggerService.info(
        '✅ STANDARD FLUTTER: updateMediaItem() called with title="${mediaItem.title}", artist="${mediaItem.artist}"');

    // STANDARD APPROACH: Let audio_service handle lockscreen on ALL platforms!
    // This is how EVERY Flutter audio app works - audio_service handles:
    // - iOS: MPNowPlayingInfoCenter + artwork download
    // - Android: MediaSession + notification
    // - Lifecycle events, caching, everything!

    _currentMediaItem = mediaItem;
    this.mediaItem.add(mediaItem); // ✅ LET THE FRAMEWORK DO ITS JOB!

    LoggerService.info(
        '✅ STANDARD FLUTTER: MediaItem set - audio_service will handle lockscreen/notification');
    LoggerService.info(
        '✅ Artwork URL: ${mediaItem.artUri?.toString() ?? "none"}');
  }

  // ANDROID: deep diagnostics helper - does not change behavior
  void _debugDumpAndroidState(String where) {
    if (!Platform.isAndroid) return;
    try {
      final ps = _player.processingState;
      final isPlaying = _player.playing;
      final pb = playbackState.value;
      final mi = mediaItem.valueOrNull;
      final tag = _currentMediaItem; // Simplified: use current MediaItem
      LoggerService.info(
          '🤖 ANDROID DIAG [$where]: player.playing=$isPlaying, player.state=$ps, '
          'pb.playing=${pb.playing}, pb.state=${pb.processingState}, '
          'mi.title="${mi?.title ?? ''}", mi.artist="${mi?.artist ?? ''}", '
          'tag.title="${tag?.title ?? ''}"');
    } catch (e) {
      LoggerService.error('🤖 ANDROID DIAG [$where] failed: $e');
    }
  }
}
