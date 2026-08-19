import 'dart:io';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/stream_constants.dart';
import '../../core/testing/debug_stream_override.dart';
import '../../core/services/logger_service.dart';
import '../../core/utils/m3u_parser.dart';
import '../../data/models/stream_metadata.dart';

/// Handles all audio-related operations including background playback
/// Modified to use a permanent dummy MediaItem to prevent just_audio_background
/// from controlling the iOS lockscreen metadata
class WBAIAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player;
  final String _configuredStreamUrl;

  /// Read per use rather than frozen at construction, so the debug outage
  /// presets take effect on the next play without restarting the app.
  /// Always the real stream in release builds.
  String get _streamUrl =>
      DebugStreamOverride.isOverridden
          ? DebugStreamOverride.effectiveUrl
          : _configuredStreamUrl;
  StreamMetadata? _currentMetadata;

  // iOS only: same channel AppDelegate listens on. Used to tell the native side
  // to re-claim the lock-screen Now Playing slot the instant play() runs.
  static const MethodChannel _nativeChannel =
      MethodChannel('com.wbaifm.radio/metadata');

  // Optional: track last buffering log time to reduce log noise
  DateTime? _lastBufferingUpdate;

  // SINGLE SOURCE OF TRUTH: One MediaItem field (like working Pacifica app)
  MediaItem? _currentMediaItem;

  // ANDROID: throttle diagnostic logs
  DateTime? _lastAndroidDiag;

  // PHASE 5: Gate the background reconnect loop. When the server is confirmed
  // down (by the repository's connecting watchdog), we halt reconnects so the
  // app isn't silently hammering a dead server behind the error modal. A fresh
  // play() re-enables it.
  bool _reconnectEnabled = true;

  // ANDROID LOCK-SCREEN BLANK FIX: True while play() is rebuilding the audio
  // source. setAudioSource() momentarily drops the player to ProcessingState.idle;
  // we use this flag in _broadcastState to (a) keep showing the current MediaItem
  // and (b) report `loading` instead of `idle` so the MediaSession never goes
  // STATE_NONE (which makes Samsung's lock screen drop the whole session).
  bool _rebuildingSource = false;

  // ANDROID LOCK-SCREEN ART FLICKER FIX: signature of the last MediaItem pushed to
  // the mediaItem stream, so _broadcastState/updateMediaItem skip redundant
  // identical pushes that otherwise re-decode + re-parcel the artwork bitmap.
  String? _lastPushedMediaSignature;

  // PHASE 10: bounded reconnect with backoff. A radio app should retry a
  // dropped stream, but not silently forever — after _maxReconnectAttempts we
  // surface an error state so the repository can classify it (server modal).
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;

  /// Exponential backoff for reconnect attempt N (1-based): 2s, 4s, 8s … capped.
  static Duration reconnectBackoff(int attempt) {
    final clamped = attempt < 1 ? 1 : attempt;
    final seconds = (1 << clamped).clamp(2, 30); // 2,4,8,16,30…
    return Duration(seconds: seconds);
  }

  WBAIAudioHandler._(
    this._player,
    this._configuredStreamUrl,
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

      // STARTUP-SPEED FIX (2026-06-24, confirmed much faster on device): this used
      // to eagerly `await _resolveStreamUrl()` + `await _player.setAudioSource()`
      // here to pre-connect the live stream at app launch. Connecting WBAI's stream
      // held up startup so the home screen sat on the "Loading stream information…"
      // placeholder. There is no reason to buffer the live stream before the user
      // presses play — play() always builds a fresh source on demand. So we DEFER
      // source setup to play() and keep startup off the
      // network's critical path. The player stays idle until play(), which is fine.

      // Only update playback state, not metadata
      // Our Swift implementation will handle the lockscreen metadata
      Future.delayed(const Duration(milliseconds: 500), () {
        _updatePlaybackStateOnly();
      });

      // Set up event listeners
      _player.processingStateStream.listen(_handleProcessingState);

      // WORKING PATTERN: Connect event streams like Pacifica app.
      // onError is the documented just_audio way to catch async playback
      // errors (e.g. the server dropping the connection mid-stream, or an
      // async load failure). Without it those errors are silently unhandled.
      _player.playbackEventStream.listen(
        _broadcastState,
        onError: _handleStreamError,
      );
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
    // ANDROID LOCK-SCREEN BLANK — THE REAL CAUSE (proven on KPFK via native logcat):
    // play() rebuilds the source via setAudioSource(), which momentarily drops the
    // player to ProcessingState.idle. Mapping that to AudioProcessingState.idle makes
    // audio_service push MediaSession PlaybackState=STATE_NONE; Samsung's lock-screen
    // widget treats a NONE session as inactive and removes the whole session (art +
    // metadata) before re-adding it ~100ms later. While we're knowingly rebuilding,
    // report `loading` instead of `idle` so the session stays active.
    final ProcessingState rawState = _player.processingState;
    final AudioProcessingState mappedState =
        (_rebuildingSource && rawState == ProcessingState.idle)
            ? AudioProcessingState.loading
            : const {
                ProcessingState.idle: AudioProcessingState.idle,
                ProcessingState.loading: AudioProcessingState.loading,
                ProcessingState.buffering: AudioProcessingState.buffering,
                ProcessingState.ready: AudioProcessingState.ready,
                ProcessingState.completed: AudioProcessingState.completed,
              }[rawState]!;

    playbackState.add(playbackState.value.copyWith(
      // SINGLE CONTROL (ported from KPFK): show only one play/pause button in the
      // notification/lock screen — the redundant stop ("X") button was removed.
      controls: [
        if (_player.playing) MediaControl.pause else MediaControl.play,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
      },
      androidCompactActionIndices: const [0],
      processingState: mappedState,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: 0,
    ));

    // PACIFICA PATTERN: Simple MediaItem management (SINGLE SOURCE OF TRUTH)
    // Only show player when we have real metadata or when actively playing.
    // `|| _rebuildingSource` keeps the player shown through setAudioSource()'s
    // transient idle so the notification never blanks to a placeholder mid-play.
    final shouldShowPlayer = (_player.processingState != ProcessingState.idle ||
            _rebuildingSource) &&
        _currentMediaItem != null &&
        (_currentMediaItem!.title != "WBAI 99.5 FM" || _player.playing);

    // The value we would push this cycle (iOS never pushes null; Android gates on
    // shouldShowPlayer).
    final MediaItem? effectiveItem =
        (Platform.isIOS && _currentMediaItem != null)
            ? _currentMediaItem
            : (shouldShowPlayer ? _currentMediaItem : null);

    // ANDROID LOCK-SCREEN ART FLICKER FIX: _broadcastState fires in a rapid burst
    // during play; re-adding an identical MediaItem each time makes audio_service
    // re-decode + re-parcel the full artwork bitmap, blanking the Samsung lock-screen
    // image. Only push when the item actually changes (title/artist/art or null↔item).
    final String pushSignature = effectiveItem == null
        ? '<null>'
        : '${effectiveItem.title}|${effectiveItem.artist}|${effectiveItem.artUri}';

    if (pushSignature != _lastPushedMediaSignature) {
      _lastPushedMediaSignature = pushSignature;
      mediaItem.add(effectiveItem);
    }
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
    // NOTE: `completed` is handled in _handleProcessingState, which actually
    // recovers (reconnects). It used to ALSO be handled here by calling
    // _handleError — which only writes a log line — giving the false impression
    // the case was covered. Deliberately not duplicated. See docs/audio-play-bug.md.
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
        // A 24/7 live stream HAS NO END. Reaching `completed` therefore always
        // means the stream died — typically the buffer drained with a dead
        // socket behind it. It is NEVER a normal end of playback.
        //
        // This used to fall through to a log line and nothing else, which is
        // exactly why the "plays the cache then STOPS" bug was silent: no
        // reconnect, no error, no modal — the app just went quiet.
        // See docs/audio-play-bug.md.
        LoggerService.audioError(
            '🎵 AUDIO STATE: Completed on a LIVE stream = stream died - reconnecting');
        if (_reconnectEnabled) {
          _reconnect();
        } else {
          // Reconnect is halted (server confirmed down / user dismissed).
          // Surface the failure rather than dying quietly.
          playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ));
        }
        break;
    }
  }

  /// LOG ONLY — this does NOT recover, retry, or change state.
  ///
  /// Named `_handleError` historically, which read as "the error is handled"
  /// and hid a release-blocking bug: the live-stream `completed` path called
  /// this and nothing else, so a dead stream produced one log line and silence.
  /// Callers that need recovery MUST invoke _reconnect() or set an error
  /// playbackState themselves. See docs/audio-play-bug.md.
  void _handleError(dynamic error) {
    LoggerService.audioError('Audio error (logged only, not recovered)', error);
  }

  // Samsung/Android: pressing a media button while the stream is loading causes
  // the native codec to flush with PlatformException(abort). This is a deliberate
  // platform-level interruption, not a network failure. Reconnecting on abort
  // triggers a 3-attempt error storm and surfaces a false "Stream playback error".
  bool _isAbortError(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('abort') || s.contains('connection aborted');
  }

  /// Handles async errors from the playback event stream (e.g. the server
  /// dropping the connection mid-stream). Triggers the gated reconnect loop;
  /// when reconnect has been halted (server confirmed down) we leave it alone.
  void _handleStreamError(Object error, StackTrace stackTrace) {
    LoggerService.audioError('Playback stream error', error);
    if (_isAbortError(error)) {
      LoggerService.info(
          '🎵 Stream aborted by platform (media button during load) — stopping, not reconnecting');
      return;
    }
    if (_reconnectEnabled) {
      _reconnect();
    }
  }

  /// PHASE 5: Stop the background reconnect loop. Called by the repository
  /// once the server is confirmed down, so we don't keep retrying behind the
  /// error modal. Re-enabled by the next play().
  void haltReconnect() {
    if (_reconnectEnabled) {
      LoggerService.info('🎵 Reconnect loop halted (server confirmed down)');
    }
    _reconnectEnabled = false;
  }

  Future<void> _reconnect() async {
    if (!_reconnectEnabled) {
      LoggerService.info('🎵 Reconnect skipped - loop is halted');
      return;
    }

    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      // PHASE 10: stop retrying and surface an error so the repository can
      // classify it (server modal) instead of reconnecting silently forever.
      LoggerService.audioError(
          '🎵 Reconnect exhausted after $_maxReconnectAttempts attempts - surfacing error',
          null);
      _reconnectEnabled = false;
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
      ));
      return;
    }

    try {
      LoggerService.info(
          '🎵 Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts...');

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
      _reconnectAttempts = 0; // success - reset the counter
      LoggerService.info('🎵 Reconnection successful');
    } catch (e) {
      LoggerService.audioError('Error during reconnection', e);
      _handleError(e);

      if (_isAbortError(e)) {
        LoggerService.info(
            '🎵 Reconnect aborted by platform — halting retry loop');
        _reconnectEnabled = false;
        return;
      }

      // Schedule another reconnect attempt with backoff (unless halted).
      final delay = reconnectBackoff(_reconnectAttempts);
      LoggerService.info(
          '🎵 Reconnect attempt failed - retrying in ${delay.inSeconds}s');
      Future.delayed(delay, () {
        if (_reconnectEnabled && !_player.playing) {
          _reconnect();
        }
      });
    }
  }

  @override
  Future<void> play() async {
    try {
      // iOS LOCK-SCREEN FLASH FIX: This runs for EVERY play — the in-app button
      // AND the lock-screen button both reach here. Reclaim the Now Playing slot
      // for WBAI *immediately*, from the native cache, BEFORE the source rebuild
      // below. Without this, the lock-screen slot belongs to the previously-used
      // audio app (Spotify/Music) during the ~2.6s reconnect and its art/metadata
      // flash before WBAI appears.
      //
      // This is the ONLY correct place to fix the flash. Do NOT suppress it by
      // resuming a stale buffer in the rebuild below — see docs/audio-play-bug.md.
      if (Platform.isIOS) {
        try {
          await _nativeChannel.invokeMethod('reassertNowPlaying');
        } catch (e) {
          LoggerService.error('reassertNowPlaying failed: $e');
        }
      }

      // PHASE 5/10: a fresh play attempt re-enables the reconnect loop that a
      // prior server-down may have halted, and resets the attempt counter.
      _reconnectEnabled = true;
      _reconnectAttempts = 0;

      // CRITICAL: Request audio focus before playing (Samsung requirement)
      final session = await AudioSession.instance;
      final success = await session.setActive(true);
      if (!success) {
        LoggerService.warning('AudioHandler: Failed to gain audio focus');
      }

      // ══════════════════════════════════════════════════════════════════
      // MANDATE (do not weaken, do not add a fast path):
      //   The play button ALWAYS plays the LIVE stream and NEVER the cache.
      // ══════════════════════════════════════════════════════════════════
      //
      // play() therefore rebuilds the AudioSource UNCONDITIONALLY, on every
      // invocation, on every platform. There is deliberately no branch here.
      //
      // HISTORY — why a branch existed, and why it must never come back
      // (full writeup: docs/audio-play-bug.md, ported from KPFK 2026-08-18):
      //
      // A "resume in place" fast path gated on
      //   sourceAlive = audioSource != null && processingState != idle
      // was added to hide the ~2.6s `setAudioSource()` gap during which iOS
      // leaves the lock-screen Now Playing slot on the previously-used audio
      // app (Spotify/Music), whose art flashes.
      //
      // But `sourceAlive` answers "does an AVPlayerItem object still exist?".
      // It does NOT answer "is the socket to the stream still open and
      // delivering live bytes?" — and for a LIVE stream only the second
      // question matters. After the app sits dormant, iOS suspends networking
      // and the server drops the idle client; the socket is dead, but AVPlayer
      // still holds the bytes it had already buffered. Resuming played that
      // stale buffer — audio from minutes ago, i.e. THE CACHE — and then died
      // when it drained, reporting `completed` and stopping silently.
      //
      // Elapsed time is not a fix either: a 5-second-old pause can have a dead
      // socket just as easily as a 5-minute-old one. There is no safe window,
      // so there is no window.
      //
      // On KPFK this was device-proven on 2026-08-18: with the rebuild made
      // unconditional, switching repeatedly between Spotify/Music and the radio
      // app produced NO flash — the native `reassertNowPlaying` pre-claim
      // already handles it on its own. Rebuilding costs ~1.5s play→Ready, well
      // under the 2.6s that motivated the shortcut. If a flash ever appears,
      // fix it in the NATIVE pre-claim — never by reintroducing a conditional
      // resume here.
      //
      // test/live_stream_always_rebuilds_test.dart guards this invariant.
      LoggerService.info(
          '🎯 LIVE-ONLY: rebuilding AudioSource from the live edge (unconditional)');
      // Guard the transient idle that setAudioSource emits so _broadcastState
      // keeps the MediaItem and reports `loading` (not idle/STATE_NONE) —
      // otherwise the Samsung lock screen drops the session and blanks.
      _rebuildingSource = true;
      try {
        final directStreamUrl = await _resolveStreamUrl(_streamUrl);
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.parse(directStreamUrl),
            tag: _currentMediaItem,
          ),
        );
        LoggerService.info('🎯 LIVE-ONLY: Fresh AudioSource set at live edge');
      } finally {
        _rebuildingSource = false;
      }

      await _player.play();

      _updateMediaSession(_player.playing, _currentMediaItem!);

      if (Platform.isAndroid) {
        _debugDumpAndroidState('play:afterUpdateSession');
      }
    } catch (e) {
      LoggerService.audioError('Error playing stream', e);
      _handleError(e);
      if (!_isAbortError(e)) {
        _reconnect();
      }
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();

      // NOTE: Do NOT call session.setActive(false) here.
      // Keeping the audio session active ensures iOS maintains this app as the
      // "Now Playing" app, preventing another app's metadata from briefly
      // appearing on the lock screen during the pause→play reconnect gap.
      // final session = await AudioSession.instance;
      // await session.setActive(false);

      _updateMediaSession(_player.playing, _currentMediaItem!);
    } catch (e) {
      LoggerService.audioError('Error pausing stream', e);
      _handleError(e);
    }
  }

  /// Called by audio_service when the app's task is swiped away from recents.
  /// `android:stopWithTask="true"` alone is unreliable for a foreground media
  /// service on Android 8.x. A full stop() here tears down playback and clears the
  /// notification regardless of whether we were playing or paused at close.
  @override
  Future<void> onTaskRemoved() async {
    LoggerService.info(
        '🎯 onTaskRemoved: app swiped from recents - stopping to clear notification tray');
    await stop();
    await super.onTaskRemoved();
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();

      final session = await AudioSession.instance;
      await session.setActive(false);

      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));

      mediaItem.add(null);
      // Keep the dedup signature in sync so a later play() is not skipped as
      // "unchanged" and correctly re-pushes the MediaItem.
      _lastPushedMediaSignature = '<null>';

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
    // SINGLE CONTROL (ported from KPFK): only one play/pause button, no stop.
    final controls = [
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
        androidCompactActionIndices: const [0],
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
      // ANDROID LOCK-SCREEN ART FIX: preserve the last-known real artwork. This
      // internal builder runs on play() too; dropping artUri here strips the art
      // from _currentMediaItem and blanks the lock-screen image until the next
      // metadata poll re-adds it. Carry the existing art forward.
      artUri: _currentMediaItem?.artUri,
    );

    // Let _broadcastState handle the mediaItem.add() call (SINGLE SOURCE OF TRUTH)
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
      // stop() — not pause() — so the reset is genuinely COLD: it tears the
      // loaded source down instead of leaving a buffered one behind. A "cold
      // start" that left audio buffered was one of the feeders of the
      // stale-cache bug. See docs/audio-play-bug.md (D8).
      await _player.stop();

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

      // Fetch M3U playlist content. The timeout matters: play() now always
      // rebuilds through here, and on a half-open network after resume an
      // untimed GET can hang forever behind the spinner. On timeout we fall
      // through to the catch below, which returns the original URL. (D7)
      //
      // WBAI currently streams a DIRECT url, so this path early-returns and
      // never fires — the timeout is here for parity, and matters the moment
      // WBAI migrates to an M3U playlist like KPFK.
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
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

    // Dedup: skip the push when nothing changed so audio_service doesn't re-decode/
    // re-parcel the artwork bitmap (Samsung lock-screen flicker). Shares the same
    // signature as _broadcastState so the two paths stay in sync.
    final String pushSignature =
        '${mediaItem.title}|${mediaItem.artist}|${mediaItem.artUri}';
    if (pushSignature != _lastPushedMediaSignature) {
      _lastPushedMediaSignature = pushSignature;
      this.mediaItem.add(mediaItem);
    }
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
