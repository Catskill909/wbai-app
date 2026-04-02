import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wbai_radio/services/audio_service/wbai_audio_handler.dart';
import '../core/services/logger_service.dart';
import '../core/services/audio_state_manager.dart';
import '../core/di/service_locator.dart';
import '../data/repositories/stream_repository.dart';

/// Service to interact with native iOS code for lockscreen metadata
class NativeMetadataService {
  // CRITICAL: This must match the channel name in AppDelegate.swift
  static const MethodChannel _channel =
      MethodChannel('com.wbaifm.radio/metadata');

  // CRITICAL FIX: Timer to periodically keep iOS audio session alive
  static Timer? _audioSessionKeepAliveTimer;

  // Reference to the audio handler (must be set externally)
  static late WBAIAudioHandler audioHandler;

  // Register the MethodCallHandler for remote commands from iOS
  static void registerRemoteCommandHandler() {
    LoggerService.info('🔒 NATIVE: Registering remote command handler');

    // CRITICAL FIX: Start the audio session keep-alive timer
    _startAudioSessionKeepAliveTimer();

    _channel.setMethodCallHandler((call) async {
      LoggerService.info('🔒 REMOTE COMMAND RECEIVED: ${call.method}');

      try {
        switch (call.method) {
          case 'remotePlay':
            LoggerService.info(
                '🔒 REMOTE COMMAND: Play triggered from iOS lockscreen');
            // CRITICAL FIX: Route directly through existing StreamRepository singleton
            // This ensures proper audio handler execution and UI synchronization
            try {
              final streamRepository = getIt<StreamRepository>();
              await streamRepository.play(
                  source: AudioCommandSource.lockscreen);
              LoggerService.info(
                  '🔒 REMOTE COMMAND: Play executed through StreamRepository');
            } catch (e) {
              LoggerService.error('🔒 REMOTE COMMAND: Play failed: $e');
              return false;
            }
            return true;

          case 'remotePause':
            LoggerService.info(
                '🔒 REMOTE COMMAND: Pause triggered from iOS lockscreen');
            // CRITICAL FIX: Route directly through existing StreamRepository singleton
            // This ensures proper audio handler execution and UI synchronization
            try {
              final streamRepository = getIt<StreamRepository>();
              await streamRepository.pause(
                  source: AudioCommandSource.lockscreen);
              LoggerService.info(
                  '🔒 REMOTE COMMAND: Pause executed through StreamRepository');
            } catch (e) {
              LoggerService.error('🔒 REMOTE COMMAND: Pause failed: $e');
              return false;
            }
            return true;

          case 'remoteTogglePlayPause':
            LoggerService.info(
                '🔒 REMOTE COMMAND: TogglePlayPause triggered from iOS lockscreen');
            // CRITICAL FIX: Route directly through StreamRepository with proper state checking
            try {
              final streamRepository = getIt<StreamRepository>();
              final currentState = streamRepository.currentState;

              if (currentState == StreamState.playing) {
                await streamRepository.pause(
                    source: AudioCommandSource.lockscreen);
                LoggerService.info(
                    '🔒 REMOTE COMMAND: Toggle -> Pause executed through StreamRepository');
              } else {
                await streamRepository.play(
                    source: AudioCommandSource.lockscreen);
                LoggerService.info(
                    '🔒 REMOTE COMMAND: Toggle -> Play executed through StreamRepository');
              }
            } catch (e) {
              LoggerService.error('🔒 REMOTE COMMAND: Toggle failed: $e');
              return false;
            }
            return true;

          case 'channelTest':
            // Handle test message from Swift
            LoggerService.info('🔒 NATIVE: Channel test received from Swift');
            return true;

          default:
            LoggerService.warning(
                '🔒 REMOTE COMMAND: Unknown method ${call.method}');
            return false;
        }
      } catch (e) {
        LoggerService.error('🔒 REMOTE COMMAND ERROR: ${e.toString()}');
        return false;
      }
    });

    // Send a test message to verify the channel is working
    _testChannel();
  }

  // CRITICAL FIX: Periodically ping iOS to keep audio session alive
  static void _startAudioSessionKeepAliveTimer() {
    _audioSessionKeepAliveTimer?.cancel();
    _audioSessionKeepAliveTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) {
      _keepAudioSessionAlive();
    });
    LoggerService.info('🔒 NATIVE: Started audio session keep-alive timer');
  }

  // CRITICAL FIX: Ping iOS to refresh the audio session
  static Future<void> _keepAudioSessionAlive() async {
    if (!Platform.isIOS) return;

    try {
      LoggerService.info('🔒 NATIVE: Sending keepAudioSessionAlive to iOS');
      final result = await _channel.invokeMethod('keepAudioSessionAlive');
      LoggerService.info('🔒 NATIVE: Audio session keep-alive result: $result');
    } catch (e) {
      LoggerService.error('🔒 NATIVE: Audio session keep-alive failed: $e');
    }
  }

  // Test the channel connection
  static Future<void> _testChannel() async {
    try {
      LoggerService.info('🔒 NATIVE: Testing channel connection to Swift');
      final result =
          await _channel.invokeMethod('channelTest', {'source': 'flutter'});
      LoggerService.info('🔒 NATIVE: Channel test result: $result');
    } catch (e) {
      LoggerService.error('🔒 NATIVE: Channel test failed: $e');
    }
  }

  // Track the last metadata update time to avoid too frequent updates
  DateTime? _lastUpdateTime;

  // Store the last metadata parameters for comparison
  String? _lastTitle;
  String? _lastArtist;
  String? _lastArtworkUrl;
  bool _lastPlayingState = false;

  // Constants to control refresh behavior
  static const Duration _throttleInterval = Duration(seconds: 5);

  /// LEGACY METHOD - Use updateLockscreenMetadata instead
  /// This method is kept for backward compatibility
  @Deprecated('Use updateLockscreenMetadata instead')
  Future<bool> updateMetadata({
    required String title,
    required String artist,
    String? artworkUrl,
    bool forceUpdate = false,
    bool isPlaying = true,
  }) async {
    return updateLockscreenMetadata(
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
      forceUpdate: forceUpdate,
      isPlaying: isPlaying,
    );
  }

  /// SINGLE SOURCE OF TRUTH: Update the iOS lockscreen with show metadata
  /// This is the ONLY method that should be used to update lockscreen metadata
  Future<bool> updateLockscreenMetadata({
    required String title,
    required String artist,
    String? artworkUrl,
    bool forceUpdate = false,
    bool isPlaying = true, // CRITICAL: Track playback state
  }) async {
    // Only run on iOS
    if (!Platform.isIOS) return false;

    // === BEGIN PLACEHOLDER GUARD ===
    final placeholderTitles = [
      'Loading stream...',
      'Connecting...',
      '',
      'WPFW Radio',
      'WPFW Stream'
    ];
    final placeholderArtists = ['Connecting...', '', 'Live Stream'];
    final isPlaceholderTitle = placeholderTitles.contains(title.trim());
    final isPlaceholderArtist = placeholderArtists.contains(artist.trim());
    if (isPlaceholderTitle || isPlaceholderArtist) {
      LoggerService.info(
          '🔒 [BLOCKED] Placeholder metadata blocked from iOS lockscreen update: title="$title", artist="$artist"');
      return false;
    }
    // === END PLACEHOLDER GUARD ===

    // Store metadata for comparison and significant change check
    _lastTitle = title;
    _lastArtist = artist;
    _lastArtworkUrl = artworkUrl;
    _lastPlayingState = isPlaying;

    // Check if this is a significant metadata change to avoid redundant updates
    final isSignificantChange =
        _isSignificantMetadataChange(title, artist, artworkUrl, isPlaying);

    // Throttle updates unless forced or significant change
    final now = DateTime.now();
    if (!forceUpdate && !isSignificantChange && _lastUpdateTime != null) {
      final difference = now.difference(_lastUpdateTime!);
      if (difference < _throttleInterval) {
        LoggerService.info(
            '🔒 NATIVE: Throttling metadata update (last update ${difference.inSeconds}s ago)');
        return true; // Still return true as the update is intentionally throttled
      }
    }
    _lastUpdateTime = now;

    try {
      LoggerService.info('🔒 NATIVE: Updating iOS lockscreen metadata');
      LoggerService.info(
          '🔒 NATIVE: Title="$title", Artist="$artist", IsPlaying=$isPlaying');

      // Ensure we have valid data
      if (title.isEmpty) {
        LoggerService.error('🔒 NATIVE: Empty title provided');
        title = 'WPFW Radio';
      }

      if (artist.isEmpty) {
        LoggerService.error('🔒 NATIVE: Empty artist provided');
        artist = 'Live Stream';
      }

      // Create metadata map with playback state
      final Map<String, dynamic> metadata = {
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying, // CRITICAL: Pass playback state to native code
        // Add forceUpdate flag so Swift knows if it should bypass its cache check
        // Although Swift's debounce might make this less critical
        'forceUpdate': forceUpdate,
      };

      // Add artwork if available
      if (artworkUrl != null && artworkUrl.isNotEmpty) {
        metadata['artworkUrl'] = artworkUrl;
        LoggerService.info(
            '🔒 NATIVE: Including artwork URL in metadata: $artworkUrl');
      } else {
        LoggerService.info(
            '🔒 NATIVE: No artwork URL provided (artworkUrl: $artworkUrl)');
      }

      // Log the complete metadata being sent
      LoggerService.info(
          '🔒 NATIVE: Sending complete metadata to iOS: $metadata');

      // Send to native code
      await _channel.invokeMethod('updateMetadata', metadata);
      LoggerService.info(
          '🔒 NATIVE: Lockscreen metadata updated successfully via invokeMethod');

      return true;
    } catch (e) {
      LoggerService.error('🔒 NATIVE: Failed to update lockscreen: $e');
      return false;
    }
  }

  /// Determines if metadata has changed significantly enough to warrant an immediate update
  bool _isSignificantMetadataChange(
      String title, String artist, String? artworkUrl, bool isPlaying) {
    // If we've never updated before, it's a significant change
    // Use _lastTitle check as a proxy for first update, as _lastUpdateTime is set after this check
    if (_lastTitle == null) return true;

    // If the playback state has changed, it's significant
    if (_lastPlayingState != isPlaying) return true;

    // If the title or artist has changed, it's significant
    if (_lastTitle != title || _lastArtist != artist) return true;

    // If artwork URL has changed (covers new artwork or artwork removal)
    if (_lastArtworkUrl != artworkUrl) return true;

    // Otherwise, it's not significant enough to bypass throttling
    return false;
  }

  /// Dispose method to clean up resources if needed
  void dispose() {
    // CRITICAL FIX: Cancel keep-alive timer
    _audioSessionKeepAliveTimer?.cancel();
    _audioSessionKeepAliveTimer = null;
    LoggerService.info('🔒 NATIVE: NativeMetadataService disposed');
  }
}
