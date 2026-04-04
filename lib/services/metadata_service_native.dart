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
    _startAudioSessionKeepAliveTimer();

    _channel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'remotePlay':
            try {
              await getIt<StreamRepository>().play(source: AudioCommandSource.lockscreen);
            } catch (e) {
              LoggerService.error('Remote play failed: $e');
              return false;
            }
            return true;

          case 'remotePause':
            try {
              await getIt<StreamRepository>().pause(source: AudioCommandSource.lockscreen);
            } catch (e) {
              LoggerService.error('Remote pause failed: $e');
              return false;
            }
            return true;

          case 'remoteTogglePlayPause':
            try {
              final repo = getIt<StreamRepository>();
              if (repo.currentState == StreamState.playing) {
                await repo.pause(source: AudioCommandSource.lockscreen);
              } else {
                await repo.play(source: AudioCommandSource.lockscreen);
              }
            } catch (e) {
              LoggerService.error('Remote toggle failed: $e');
              return false;
            }
            return true;

          case 'channelTest':
            return true;

          default:
            return false;
        }
      } catch (e) {
        LoggerService.error('Remote command error: ${e.toString()}');
        return false;
      }
    });

    _testChannel();
  }

  // CRITICAL FIX: Periodically ping iOS to keep audio session alive
  static void _startAudioSessionKeepAliveTimer() {
    _audioSessionKeepAliveTimer?.cancel();
    _audioSessionKeepAliveTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) {
      _keepAudioSessionAlive();
    });
  }

  static Future<void> _keepAudioSessionAlive() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('keepAudioSessionAlive');
    } catch (e) {
      LoggerService.error('Audio session keep-alive failed: $e');
    }
  }

  static Future<void> _testChannel() async {
    try {
      await _channel.invokeMethod('channelTest', {'source': 'flutter'});
    } catch (e) {
      LoggerService.error('Channel test failed: $e');
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
        return true;
      }
    }
    _lastUpdateTime = now;

    try {
      if (title.isEmpty) title = 'WPFW Radio';
      if (artist.isEmpty) artist = 'Live Stream';

      final Map<String, dynamic> metadata = {
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
        'forceUpdate': forceUpdate,
      };

      if (artworkUrl != null && artworkUrl.isNotEmpty) {
        metadata['artworkUrl'] = artworkUrl;
      }

      await _channel.invokeMethod('updateMetadata', metadata);
      return true;
    } catch (e) {
      LoggerService.error('Failed to update lockscreen: $e');
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
    _audioSessionKeepAliveTimer?.cancel();
    _audioSessionKeepAliveTimer = null;
  }
}
