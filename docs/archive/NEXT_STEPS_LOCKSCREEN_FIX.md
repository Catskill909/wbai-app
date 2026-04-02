# NEXT STEPS: iOS Lockscreen Metadata Fix — FINAL IMPLEMENTATION

## Executive Summary

After multiple attempts to fix the iOS lockscreen metadata issue, we have identified the fundamental problems and developed a definitive solution plan. This document outlines the specific steps required to implement a true "single source of truth" approach for iOS lockscreen metadata.

## Root Cause Analysis

1. **Multiple Competing Update Mechanisms:**
   - Three separate Flutter-side triggers: metadata updates, playback state changes, and manual refreshes
   - Flutter-side throttling is bypassed by multiple update sources
   - just_audio_background continues to fight with our native implementation

2. **Excessive Update Frequency:**
   - Metadata updates are triggered too frequently (multiple times per second)
   - The 500ms delayed double-update pattern creates race conditions
   - State changes (buffering, connecting, etc.) trigger additional metadata updates

3. **Placeholder Metadata Overrides:**
   - Placeholder values ("Loading stream...", "Connecting...") override valid metadata after playback resumes
   - Insufficient guards to prevent placeholder metadata from reaching the lockscreen

## Implementation Plan

### 1. Create TRUE Single Source of Truth

**A. Consolidate All Metadata Update Paths**

```dart
// CRITICAL: This will be the ONLY method that can update lockscreen metadata
Future<void> updateLockscreenMetadata({
  required String title,
  required String artist,
  String? artworkUrl,
  required bool isPlaying,
}) async {
  // Skip if not iOS
  if (!Platform.isIOS) return;

  // 1. Skip placeholder metadata
  if (_isPlaceholderMetadata(title, artist)) {
    LoggerService.info('🔒 Blocking placeholder metadata: "$title", "$artist"');
    return;
  }

  // 2. Skip if not significant change (unless playback state changed)
  final isSignificantChange = _isSignificantChange(title, artist, isPlaying);
  if (!isSignificantChange) {
    LoggerService.info('🔒 Skipping non-significant metadata update');
    return;
  }

  // 3. Send to native layer (ONE path only)
  try {
    await _channel.invokeMethod('setLockscreenMetadata', {
      'title': title,
      'artist': artist,
      'artworkUrl': artworkUrl,
      'isPlaying': isPlaying,
    });
    LoggerService.info('🔒 Sent metadata to native: "$title", "$artist", playing=$isPlaying');
  } catch (e) {
    LoggerService.error('🔒 Failed to update lockscreen: $e');
  }
}
```

**B. Block ALL Other Update Paths**

```dart
// CRITICAL: REMOVE or BLOCK these paths
// 1. Remove double-update pattern in refreshMetadata()
// 2. Remove _updateLockscreenOnPlaybackChange() call from playback state listener
// 3. Ensure WPFWAudioHandler NEVER updates lockscreen metadata directly
```

### 2. iOS Native Implementation (Single Gatekeeper)

```swift
// CRITICAL: Single handler with debounce to prevent flickering
private var pendingMetadataUpdate: [String: Any]?
private var metadataDebounceTimer: Timer?
private let debounceInterval: TimeInterval = 0.25 // 250ms

func handleSetLockscreenMetadata(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let title = args["title"] as? String,
          let artist = args["artist"] as? String,
          let isPlaying = args["isPlaying"] as? Bool else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        return
    }
    
    // Guard against placeholder metadata (defense in depth)
    if isPlaceholderMetadata(title: title, artist: artist) {
        print("[METADATA] Blocked placeholder metadata: \"\(title)\", \"\(artist)\"")
        result(true) // Still return success
        return
    }
    
    // Store pending update
    pendingMetadataUpdate = args
    
    // Debounce updates
    metadataDebounceTimer?.invalidate()
    metadataDebounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
        self?.applyPendingMetadataUpdate()
    }
    
    // Return immediately
    result(true)
}

private func applyPendingMetadataUpdate() {
    // Must be called on main thread
    DispatchQueue.main.async {
        guard let update = self.pendingMetadataUpdate else { return }
        
        // Extract values
        let title = update["title"] as? String ?? "WPFW Radio"
        let artist = update["artist"] as? String ?? "WPFW"
        let isPlaying = update["isPlaying"] as? Bool ?? false
        let artworkUrl = update["artworkUrl"] as? String
        
        print("[METADATA] Applying debounced update: \"\(title)\" by \"\(artist)\", playing=\(isPlaying)")
        
        // Build metadata dictionary
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: "WPFW 89.3 FM",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        // Set the metadata
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        // Load artwork asynchronously if provided
        if let artworkUrlString = artworkUrl, let url = URL(string: artworkUrlString) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
                
                DispatchQueue.main.async {
                    // Get current info and update just the artwork
                    var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? nowPlayingInfo
                    currentInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                    print("[METADATA] Added artwork to lockscreen")
                }
            }.resume()
        }
        
        // Clear pending update
        self.pendingMetadataUpdate = nil
    }
}

private func isPlaceholderMetadata(title: String, artist: String) -> Bool {
    let placeholderTitles = ["Loading stream...", "Connecting...", "", "WPFW Radio", "WPFW Stream"]
    let placeholderArtists = ["Connecting...", "", "Live Stream"]
    return placeholderTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines)) ||
           placeholderArtists.contains(artist.trimmingCharacters(in: .whitespacesAndNewlines))
}
```

### 3. just_audio_background Isolation

```dart
// CRITICAL: Prevent just_audio_background from updating lockscreen metadata

// 1. In WPFWAudioHandler.updateMediaItem():
@override
Future<void> updateMediaItem(MediaItem mediaItem) async {
  // CRITICAL: Do NOT update the mediaItem stream
  // This prevents just_audio_background from controlling the lockscreen
  // Instead, only update the playback state
  
  LoggerService.info('🎵 BLOCKING MediaItem update from affecting lockscreen');
  
  // Only update playback state
  playbackState.add(playbackState.value.copyWith(
    playing: _player.playing,
    processingState: playbackState.value.processingState,
    updatePosition: _player.position,
    speed: _player.speed,
  ));
}
```

### 4. Simplify StreamRepository Integration

```dart
// CRITICAL: Consolidate all metadata update calls to a single path

class StreamRepository {
  // ...existing code...
  
  // This becomes the ONLY method that triggers lockscreen updates
  void _handleMetadataUpdate(StreamMetadata metadata) {
    if (metadata == null) return;
    
    // Update local state
    _currentMetadata = metadata;
    _metadataController.add(metadata);
    
    // Format metadata for display
    final showInfo = metadata.current;
    final title = showInfo.showName.isNotEmpty ? showInfo.showName : 'WPFW Radio';
    String artist;
    
    if (showInfo.hasSongInfo && showInfo.songTitle != null && showInfo.songTitle!.isNotEmpty) {
      artist = showInfo.songArtist != null && showInfo.songArtist!.isNotEmpty
          ? 'Playing: ${showInfo.songTitle} - ${showInfo.songArtist}'
          : 'Playing: ${showInfo.songTitle}';
    } else {
      artist = showInfo.host.isNotEmpty ? 'Host: ${showInfo.host}' : 'WPFW 89.3 FM';
    }
    
    // Get current playback state
    final isPlaying = _audioHandler.playbackState.value.playing;
    
    // SINGLE update path - all other paths must be removed or disabled
    NativeMetadataService.instance.updateLockscreenMetadata(
      title: title,
      artist: artist,
      artworkUrl: showInfo.hostImage,
      isPlaying: isPlaying,
    );
  }
  
  // REMOVE all other methods that call updateMetadata
}
```

## Implementation Checklist

1. [ ] Create singleton NativeMetadataService with true single update method
2. [ ] Block or remove ALL other update paths (especially the double-update pattern)
3. [ ] Implement debounced metadata handler in AppDelegate.swift
4. [ ] Add comprehensive placeholder metadata guards on both sides
5. [ ] Remove direct calls from playback state change listener
6. [ ] Test all scenarios: play, pause, stop, metadata updates, app launch
7. [ ] Verify no placeholder metadata ever reaches lockscreen during playback
8. [ ] Review logs to confirm only necessary updates are sent to native layer

## Verification

After implementation, verify the fix by monitoring the logs. You should see:

1. Clear, single-path metadata updates
2. Effective debouncing with less frequent updates
3. No placeholder metadata during playback
4. Stable lockscreen display without flickering

## References

- [LOCKSCREEN_METADATA_SINGLE_SOURCE.md](./LOCKSCREEN_METADATA_SINGLE_SOURCE.md)
- [iOS_FUNDAMENTAL_ISSUES.md](./iOS_FUNDAMENTAL_ISSUES.md)
- [FINAL_ATTEMPT_LOGS_ANALYSIS.md](./FINAL_ATTEMPT_LOGS_ANALYSIS.md)

---

Document prepared: April 18, 2025
