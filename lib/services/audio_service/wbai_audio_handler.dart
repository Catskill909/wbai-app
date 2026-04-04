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
  }

  static Future<WBAIAudioHandler> create() async {
    final player = AudioPlayer();

    return WBAIAudioHandler._(
      player,
      StreamConstants.streamUrl,
    );
  }

  Future<void> _init() async {
    try {
      // Configure audio session category - do NOT activate until user presses play
      // Activating at startup causes iOS paramErr (-50) before foreground audio is allowed
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // EXPERT SOLUTION: Parse M3U playlist to get direct stream URL
      final directStreamUrl = await _resolveStreamUrl(_streamUrl);
      LoggerService.info('AudioHandler: Resolved stream URL: $directStreamUrl');

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

      if (Platform.isAndroid) {
        playbackState.listen((state) {
          // throttle diagnostic dumps
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
      // CRITICAL: Request audio focus before playing (Samsung requirement)
      final session = await AudioSession.instance;
      final success = await session.setActive(true);
      if (!success) {
        LoggerService.warning('AudioHandler: Failed to gain audio focus');
      }

      // CACHE FIX: ALWAYS set fresh AudioSource - never trust existing one
      final directStreamUrl = await _resolveStreamUrl(_streamUrl);
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(directStreamUrl),
          tag: _currentMediaItem,
        ),
      );

      await _player.play();

      _updateMediaSession(_player.playing, _currentMediaItem!);

      await SamsungMediaSessionService.updatePlaybackState(true);

      if (_currentMetadata != null) {
        await SamsungMediaSessionService.updateMetadata(
          _currentMetadata!.currentSong,
          _currentMetadata!.artist,
        );
      }

      await SamsungMediaSessionService.showNotification();

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
      await _player.pause();

      final session = await AudioSession.instance;
      await session.setActive(false);

      _updateMediaSession(_player.playing, _currentMediaItem!);

      await SamsungMediaSessionService.updatePlaybackState(false);
      await SamsungMediaSessionService.hideNotification();
    } catch (e) {
      LoggerService.audioError('Error pausing stream', e);
      _handleError(e);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();

      final session = await AudioSession.instance;
      await session.setActive(false);

      await SamsungMediaSessionService.hideNotification();

      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));

      mediaItem.add(null);

      playbackState.add(PlaybackState(
        controls: [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 0.0,
      ));
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
  }

  /// Updates the current MediaItem with real metadata (SINGLE SOURCE OF TRUTH)
  Future<void> _updateMediaItem(String title, String artist) async {
    // Skip empty or placeholder updates
    if (title.isEmpty ||
        title == 'Loading stream...' ||
        title == 'Connecting...') {
      return;
    }

    // PACIFICA PATTERN: Update _currentMediaItem with real metadata
    _currentMediaItem = MediaItem(
      id: "wbai_live",
      album: "WBAI 99.5 FM",
      title: title,
      artist: artist,
      duration: const Duration(hours: 24),
    );

    // Let _broadcastState handle the mediaItem.add() call (SINGLE SOURCE OF TRUTH)
    await SamsungMediaSessionService.updateMetadata(title, artist);
  }

  /// Updates only the playback state without changing metadata
  /// This prevents iOS from caching placeholder values
  Future<void> _updatePlaybackStateOnly() async {
    playbackState.add(
      playbackState.value.copyWith(
        playing: _player.playing,
        processingState: playbackState.value.processingState,
        updatePosition: _player.position,
        speed: _player.speed,
      ),
    );
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
    _currentMetadata = metadata;
    _updateMediaItem(
      metadata.currentSong,
      metadata.artist,
    );
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    _currentMediaItem = mediaItem;
    this.mediaItem.add(mediaItem);
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
