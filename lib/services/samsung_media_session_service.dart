import 'dart:io';
import 'package:flutter/services.dart';
import '../core/services/logger_service.dart';
import '../core/di/service_locator.dart';
import '../data/repositories/stream_repository.dart';
import '../core/services/audio_state_manager.dart';

/// CRITICAL FIX: Samsung MediaSession Service
///
/// This service communicates with the native Android MediaSessionCompat
/// that Samsung devices require for proper lockscreen controls.
///
/// This bypasses Flutter's audio_service limitations and provides
/// Samsung J7 with the exact MediaSession implementation it needs.
class SamsungMediaSessionService {
  static const MethodChannel _channel =
      MethodChannel('app.pacifica.wbai/samsung_media_session');

  static bool _isInitialized = false;
  static String _currentTitle = 'WBAI 99.5 FM';
  static String _currentArtist = 'Pacifica Radio';
  static bool _isPlaying = false;

  /// Initialize the Samsung MediaSession service
  /// Only works on Android - iOS is ignored
  static Future<void> initialize() async {
    if (!Platform.isAndroid || _isInitialized) return;

    try {
      // Set up method call handler for receiving media actions from native
      _channel.setMethodCallHandler(_handleMethodCall);

      _isInitialized = true;
      LoggerService.info('🤖 SAMSUNG: MediaSession service initialized');
      // IMPORTANT: Do NOT show a notification on init.
      // We only show the media player when playback actually starts.
    } catch (e) {
      LoggerService.error(
          '🤖 SAMSUNG: Failed to initialize MediaSession service: $e');
    }
  }

  /// Handle method calls from native Android
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onMediaAction':
        final action = call.arguments['action'] as String?;
        LoggerService.info('🤖 SAMSUNG: Received media action: $action');

        // CRITICAL: Connect Samsung MediaSession to existing StreamRepository
        // This integrates Samsung lockscreen controls with your existing audio system
        try {
          final streamRepository = getIt<StreamRepository>();

          switch (action) {
            case 'play':
              LoggerService.info(
                  '🤖 SAMSUNG: Play action received from lockscreen - calling StreamRepository.play()');
              await streamRepository.play(
                  source: AudioCommandSource.lockscreen);
              break;
            case 'pause':
              LoggerService.info(
                  '🤖 SAMSUNG: Pause action received from lockscreen - calling StreamRepository.pause()');
              await streamRepository.pause(
                  source: AudioCommandSource.lockscreen);
              break;
            case 'stop':
              LoggerService.info(
                  '🤖 SAMSUNG: Stop action received from lockscreen - calling StreamRepository.pause()');
              await streamRepository.pause(
                  source: AudioCommandSource.lockscreen);
              break;
          }
        } catch (e) {
          LoggerService.error(
              '🤖 SAMSUNG: Failed to handle media action $action: $e');
        }
        break;
      case 'onAppClosing':
        // Android-only callback from MainActivity when the app is truly closing.
        // Stop and clear everything so the player is removed from the tray.
        if (!Platform.isAndroid) return null;
        try {
          LoggerService.info(
              '🤖 SAMSUNG: onAppClosing received - stopping and clearing player');
          final repo = getIt<StreamRepository>();
          await repo.stopAndColdReset(preserveMetadata: false);
          // Ensure native notification is hidden as a belt-and-suspenders
          await hideNotification();
        } catch (e) {
          LoggerService.error('🤖 SAMSUNG: Failed to handle onAppClosing: $e');
        }
        break;
    }
  }

  /// Update metadata in the Samsung MediaSession
  /// Call this whenever the song/show changes
  static Future<void> updateMetadata(String title, String artist) async {
    if (!Platform.isAndroid || !_isInitialized) return;

    _currentTitle = title;
    _currentArtist = artist;

    try {
      await _channel.invokeMethod('updateMetadata', {
        'title': title,
        'artist': artist,
      });

      LoggerService.info(
          '🤖 SAMSUNG: Updated metadata - Title: $title, Artist: $artist');
    } catch (e) {
      LoggerService.error('🤖 SAMSUNG: Failed to update metadata: $e');
    }
  }

  /// Update playback state in the Samsung MediaSession
  /// Call this whenever play/pause state changes
  static Future<void> updatePlaybackState(bool isPlaying) async {
    if (!Platform.isAndroid || !_isInitialized) return;

    _isPlaying = isPlaying;

    try {
      await _channel.invokeMethod('updatePlaybackState', {
        'isPlaying': isPlaying,
      });

      LoggerService.info(
          '🤖 SAMSUNG: Updated playback state - Playing: $isPlaying');
    } catch (e) {
      LoggerService.error('🤖 SAMSUNG: Failed to update playback state: $e');
    }
  }

  /// Show the Samsung MediaSession notification
  /// Call this when starting the app or beginning playback
  static Future<void> showNotification() async {
    if (!Platform.isAndroid || !_isInitialized) return;

    try {
      await _channel.invokeMethod('showNotification');
      LoggerService.info('🤖 SAMSUNG: MediaSession notification shown');
    } catch (e) {
      LoggerService.error('🤖 SAMSUNG: Failed to show notification: $e');
    }
  }

  /// Hide the Samsung MediaSession notification
  /// Call this when stopping playback completely
  static Future<void> hideNotification() async {
    if (!Platform.isAndroid || !_isInitialized) return;

    try {
      await _channel.invokeMethod('hideNotification');
      LoggerService.info('🤖 SAMSUNG: MediaSession notification hidden');
    } catch (e) {
      LoggerService.error('🤖 SAMSUNG: Failed to hide notification: $e');
    }
  }

  /// Get current metadata
  static Map<String, String> getCurrentMetadata() {
    return {
      'title': _currentTitle,
      'artist': _currentArtist,
    };
  }

  /// Get current playback state
  static bool get isPlaying => _isPlaying;

  /// Check if service is initialized
  static bool get isInitialized => _isInitialized;
}
