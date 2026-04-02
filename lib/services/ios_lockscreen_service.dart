import 'dart:io';
import 'package:flutter/services.dart';
import '../core/services/logger_service.dart';
import '../domain/models/stream_metadata.dart';

/// Service to directly update iOS lockscreen metadata using native code
/// This bypasses Flutter's audio plugins and directly uses MPNowPlayingInfoCenter
class IOSLockscreenService {
  // CRITICAL: This MUST match exactly the channel name in AppDelegate.swift
  static const MethodChannel _channel = MethodChannel('com.wpfwfm.radio/now_playing');
  
  /// Updates the iOS lockscreen with current show metadata
  Future<void> updateLockscreen({
    required String title,
    required String artist,
    required String album,
    String? artworkUrl,
    Duration? duration,
    Duration? position,
    bool? isPlaying,
  }) async {
    // Only run on iOS
    if (!Platform.isIOS) return;

    // === BEGIN PLACEHOLDER GUARD ===
    final placeholderTitles = ['Loading stream...', 'Connecting...', '', 'WPFW Radio', 'WPFW Stream'];
    final placeholderArtists = ['Connecting...', '', 'Live Stream'];
    final isPlaceholderTitle = placeholderTitles.contains(title.trim());
    final isPlaceholderArtist = placeholderArtists.contains(artist.trim());
    if (isPlaceholderTitle || isPlaceholderArtist) {
      LoggerService.info('🔒 [BLOCKED] Placeholder metadata blocked from iOS lockscreen update: title="$title", artist="$artist"');
      return;
    }
    // === END PLACEHOLDER GUARD ===
    
    try {
      LoggerService.info('🔒 NATIVE iOS: ===== DIRECT LOCKSCREEN UPDATE =====');
      LoggerService.info('🔒 NATIVE iOS: Title="$title", Artist="$artist"');
      
      // CRITICAL: Verify we have valid data before sending
      if (title.isEmpty) {
        LoggerService.error('🔒 NATIVE iOS: ⚠️ EMPTY TITLE - Using fallback');
        title = 'WPFW Radio';
      }
      
      if (artist.isEmpty) {
        LoggerService.error('🔒 NATIVE iOS: ⚠️ EMPTY ARTIST - Using fallback');
        artist = 'Live Stream';
      }
      
      // Create metadata map with explicit non-null values
      final Map<String, dynamic> metadata = {
        'title': title,
        'artist': artist,
        'album': album,
      };
      
      // Add optional parameters only if they have values
      if (artworkUrl != null && artworkUrl.isNotEmpty) {
        metadata['artworkUrl'] = artworkUrl;
        LoggerService.info('🔒 NATIVE iOS: Including artwork URL: $artworkUrl');
      }
      
      if (duration != null) {
        metadata['duration'] = duration.inMilliseconds;
      }
      
      if (position != null) {
        metadata['position'] = position.inMilliseconds;
      }
      
      if (isPlaying != null) {
        metadata['isPlaying'] = isPlaying;
      }
      
      LoggerService.info('🔒 NATIVE iOS: Sending metadata to platform channel: $metadata');
      
      // CRITICAL: Clear lockscreen first to break any caching
      await clearLockscreen();
      
      // Short delay to ensure clear takes effect
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Send the update
      final result = await _channel.invokeMethod('updateNowPlaying', metadata);
      LoggerService.info('🔒 NATIVE iOS: ✅ Platform channel result: $result');
    } catch (e, stackTrace) {
      LoggerService.error('🔒 NATIVE iOS: ⚠️ CRITICAL ERROR updating lockscreen: $e');
      LoggerService.error('🔒 NATIVE iOS: Stack trace: $stackTrace');
    }
  }
  
  /// Clear all metadata from the lockscreen
  Future<void> clearLockscreen() async {
    if (!Platform.isIOS) return;
    
    try {
      LoggerService.info('🔒 NATIVE iOS: Clearing lockscreen metadata');
      await _channel.invokeMethod('clearNowPlaying');
    } catch (e) {
      LoggerService.error('🔒 NATIVE iOS: Failed to clear lockscreen: $e');
    }
  }
  
  /// Update lockscreen with show metadata
  Future<void> updateWithMetadata(StreamMetadata metadata) async {
    if (!Platform.isIOS) return;
    
    final showInfo = metadata.current;
    
    // Create detailed title and artist fields
    final String title = showInfo.showName.isNotEmpty 
        ? showInfo.showName 
        : 'WPFW Radio';
    
    // Artist field will show host info and song if available
    String artist;
    if (showInfo.hasSongInfo && showInfo.songTitle != null && showInfo.songTitle!.isNotEmpty) {
      artist = showInfo.songArtist != null && showInfo.songArtist!.isNotEmpty
          ? 'Playing: ${showInfo.songTitle} - ${showInfo.songArtist}'
          : 'Playing: ${showInfo.songTitle}';
    } else {
      artist = showInfo.host.isNotEmpty ? 'Host: ${showInfo.host}' : 'WPFW 89.3 FM';
    }
    
    // Get artwork URL if available
    final String? artworkUrl = showInfo.hostImage;
    
    await updateLockscreen(
      title: title,
      artist: artist,
      album: 'WPFW 89.3 FM',
      artworkUrl: artworkUrl,
      isPlaying: true,
    );
  }
}
