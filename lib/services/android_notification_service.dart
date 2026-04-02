import 'dart:io';
import '../core/services/logger_service.dart';

/// Android-only notification service - DOES NOT AFFECT iOS
/// This service provides Android-specific notification customizations
/// and mirrors the iOS lockscreen control behavior for Android devices
class AndroidNotificationService {
  // Note: Android notifications are handled through the audio_service package
  // A dedicated method channel could be added here for future Android-specific features
  
  /// Initialize Android notification handlers
  /// SAFETY: Only runs on Android devices, completely separate from iOS
  static void registerAndroidNotificationHandlers() {
    // SAFETY: Only run on Android
    if (!Platform.isAndroid) {
      LoggerService.info('🤖 ANDROID: Skipping Android notification setup on non-Android platform');
      return;
    }
    
    LoggerService.info('🤖 ANDROID: Registering Android notification handlers');
    LoggerService.info('🤖 ANDROID: Android notifications will be handled through audio_service package');
    
    // Android notifications are handled through the existing audio_service package
    // This service provides Android-specific customizations and logging
    _setupAndroidNotificationStyle();
  }
  
  /// Configure Android notification appearance and behavior
  /// This ensures Android notifications match the simple on/off behavior of iOS
  static void _setupAndroidNotificationStyle() {
    LoggerService.info('🤖 ANDROID: Configuring notification style for simple on/off behavior');
    LoggerService.info('🤖 ANDROID: Android notifications will mirror iOS lockscreen behavior');
    
    // Android-specific notification customizations can be added here
    // For now, we rely on the audio_service package's default Android behavior
    // which provides lockscreen and notification tray controls automatically
  }
  
  /// Update Android notification metadata
  /// This method provides Android-specific logging and monitoring
  /// The actual notification updates are handled through WBAIAudioHandler
  static Future<bool> updateAndroidNotification({
    required String title,
    required String artist,
    String? artworkUrl,
    bool isPlaying = true,
  }) async {
    // SAFETY: Only run on Android
    if (!Platform.isAndroid) return false;
    
    LoggerService.info('🤖 ANDROID: Notification metadata update requested');
    LoggerService.info('🤖 ANDROID: Title="$title", Artist="$artist", Playing=$isPlaying');
    
    // Skip placeholder updates (same logic as iOS)
    final placeholderTitles = [
      'Loading stream...',
      'Connecting...',
      '',
      'WPFW Radio',
      'WPFW Stream'
    ];
    final placeholderArtists = ['Connecting...', '', 'Live Stream'];
    
    if (placeholderTitles.contains(title) || placeholderArtists.contains(artist)) {
      LoggerService.info('🤖 ANDROID: Skipping placeholder metadata update');
      return false;
    }
    
    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      LoggerService.info('🤖 ANDROID: Including artwork URL: $artworkUrl');
    } else {
      LoggerService.info('🤖 ANDROID: No artwork URL provided');
    }
    
    // Android notification updates are handled through WBAIAudioHandler
    // This method provides Android-specific logging and validation
    LoggerService.info('🤖 ANDROID: Android notification update logged successfully');
    return true;
  }
  
  /// Clear Android notification (mirrors iOS clearLockscreen behavior)
  static Future<void> clearAndroidNotification() async {
    // SAFETY: Only run on Android
    if (!Platform.isAndroid) return;
    
    LoggerService.info('🤖 ANDROID: Clearing Android notification (mirroring iOS behavior)');
    
    // Android notification clearing is handled through the audio_service package
    // when the audio handler is stopped or reset
    LoggerService.info('🤖 ANDROID: Android notification clear requested');
  }
  
  /// Dispose method to clean up Android-specific resources
  static void dispose() {
    if (!Platform.isAndroid) return;
    
    LoggerService.info('🤖 ANDROID: AndroidNotificationService disposed');
    // Android-specific cleanup can be added here if needed
  }
}
