import 'dart:io';
import 'package:flutter/services.dart';
import '../core/services/logger_service.dart';
import '../domain/models/stream_metadata.dart';

/// Service to directly update iOS lockscreen metadata using native code
/// This bypasses Flutter's audio plugins and directly uses MPNowPlayingInfoCenter
class IOSLockscreenService {
  // CRITICAL: This MUST match exactly the channel name in AppDelegate.swift
  static const MethodChannel _channel = MethodChannel('com.wbaifm.radio/now_playing');
  
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
      return;
    }
    // === END PLACEHOLDER GUARD ===

    try {
      if (title.isEmpty) title = 'WPFW Radio';
      if (artist.isEmpty) artist = 'Live Stream';

      final Map<String, dynamic> metadata = {
        'title': title,
        'artist': artist,
        'album': album,
      };

      if (artworkUrl != null && artworkUrl.isNotEmpty) {
        metadata['artworkUrl'] = artworkUrl;
      }
      if (duration != null) metadata['duration'] = duration.inMilliseconds;
      if (position != null) metadata['position'] = position.inMilliseconds;
      if (isPlaying != null) metadata['isPlaying'] = isPlaying;

      await clearLockscreen();
      await Future.delayed(const Duration(milliseconds: 200));
      await _channel.invokeMethod('updateNowPlaying', metadata);
    } catch (e, stackTrace) {
      LoggerService.error('Failed to update iOS lockscreen: $e\n$stackTrace');
    }
  }
  
  Future<String?> _resolveArtworkUrl(String? showImage, String? fallback) async {
    if (showImage != null && showImage.isNotEmpty) {
      try {
        final request = await HttpClient().headUrl(Uri.parse(showImage));
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) return showImage;
      } catch (_) {}
    }
    return fallback;
  }

  /// Clear all metadata from the lockscreen
  Future<void> clearLockscreen() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('clearNowPlaying');
    } catch (e) {
      LoggerService.error('Failed to clear iOS lockscreen: $e');
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
    
    // Use station fallback if show image is unavailable
    final String? artworkUrl = await _resolveArtworkUrl(
      showInfo.hostImage,
      metadata.stationFallbackImage,
    );

    await updateLockscreen(
      title: title,
      artist: artist,
      album: 'WBAI 99.5 FM',
      artworkUrl: artworkUrl,
      isPlaying: true,
    );
  }
}
