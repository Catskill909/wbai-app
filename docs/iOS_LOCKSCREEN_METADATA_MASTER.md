# iOS Lockscreen Metadata - Master Reference Document

## 🚨 Current Status (2025-04-18)

**Current Behavior:**
- ✅ When audio is **stopped**: Correct metadata displays stably on lockscreen
- ❌ When audio is **playing**: Metadata flickers between correct data and "Not Playing" text
- ✅ Artwork displays correctly
- ✅ Remote commands (play/pause) work correctly

**Root Causes Identified:**
1. Multiple competing update paths in the codebase
2. Excessive playback state changes triggering metadata updates
3. Placeholder metadata overriding valid data during playback
4. just_audio_background fighting with native implementation
5. UIKit lifecycle warnings affecting audio session

## Implementation History

### Approach 1: Flutter-Only Solutions (Failed)
- **audio_service + just_audio**: Failed to provide reliable lockscreen updates on iOS
- **just_audio_background**: Provided basic functionality but with inconsistent metadata display

### Approach 2: Platform Channel with MPNowPlayingInfoCenter (Current)
- **Implementation**: Dart sends metadata via MethodChannel, Swift updates lockscreen natively
- **Status**: Partially successful - works when stopped, flickers during playback

### Approach 3: Debouncing and Throttling (Partially Successful)
- **Implementation**: Added debounce timer (250ms) in Swift layer
- **Status**: Reduced but did not eliminate flickering

### Approach 4: Single Source of Truth (Current)
- **Implementation**: Consolidated all metadata updates through NativeMetadataService
- **Status**: Improved stability but still has issues during playback

### Approach 5: Reduced Update Frequency (Latest)
- **Implementation**: Removed _updateLockscreenOnPlaybackChange from playback state listener
- **Status**: Reduced update frequency but flickering still occurs during playback

## Technical Implementation Details

### Dart/Flutter Layer
```dart
// NativeMetadataService - Single source of truth for lockscreen metadata
Future<bool> updateLockscreenMetadata({
  required String title,
  required String artist,
  String? artworkUrl,
  bool forceUpdate = false,
  bool isPlaying = true,
}) async {
  // Placeholder guard
  final placeholderTitles = ['Loading stream...', 'Connecting...', '', 'WPFW Radio', 'WPFW Stream'];
  final placeholderArtists = ['Connecting...', '', 'Live Stream'];
  final isPlaceholderTitle = placeholderTitles.contains(title.trim());
  final isPlaceholderArtist = placeholderArtists.contains(artist.trim());
  
  if (isPlaceholderTitle || isPlaceholderArtist) {
    LoggerService.info('🔒 [BLOCKED] Placeholder metadata blocked from iOS lockscreen update');
    return false;
  }
  
  // Throttle updates
  final now = DateTime.now();
  if (!forceUpdate && _lastUpdateTime != null) {
    final difference = now.difference(_lastUpdateTime!);
    if (difference < _throttleInterval) {
      LoggerService.info('🔒 NATIVE: Throttling metadata update');
      return true;
    }
  }
  _lastUpdateTime = now;
  
  // Send to native code
  try {
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
    LoggerService.error('🔒 NATIVE: Failed to update lockscreen: $e');
    return false;
  }
}
```

### Swift/iOS Layer
```swift
// AppDelegate.swift - Handling metadata updates
private func handleUpdateMetadata(call: FlutterMethodCall, result: @escaping FlutterResult) {
  // Extract metadata
  guard let args = call.arguments as? [String: Any],
        let title = args["title"] as? String,
        let artist = args["artist"] as? String,
        let isPlaying = args["isPlaying"] as? Bool else {
    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
    return
  }
  
  // Skip placeholder metadata during playback
  let placeholderTitles = ["Loading stream...", "Connecting...", "", "WPFW Radio", "WPFW Stream"]
  let placeholderArtists = ["Connecting...", "", "Live Stream"]
  let isPlaceholder = placeholderTitles.contains(title) || placeholderArtists.contains(artist)
  
  if (isPlaceholder && isPlaying) {
    print("[METADATA] Blocking placeholder during playback: \(title) by \(artist)")
    result(true)
    return
  }
  
  // Skip if nothing has changed
  if title == lastTitle && artist == lastArtist && isPlaying == lastIsPlaying {
    print("[METADATA] Skipping identical update: \(title) by \(artist), playing=\(isPlaying)")
    result(true)
    return
  }
  
  // Store current values
  lastTitle = title
  lastArtist = artist
  lastIsPlaying = isPlaying
  
  // Store the entire arguments as the pending update
  pendingMetadataUpdate = args
  
  // Debounce updates (250ms)
  metadataDebounceTimer?.invalidate()
  metadataDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
    self?.applyPendingMetadataUpdate()
  }
  
  result(true)
}

// Apply the pending metadata update on the main thread
private func applyPendingMetadataUpdate() {
  DispatchQueue.main.async { [weak self] in
    guard let self = self, let update = self.pendingMetadataUpdate else { return }
    
    // Extract values
    guard let title = update["title"] as? String,
          let artist = update["artist"] as? String,
          let isPlaying = update["isPlaying"] as? Bool else {
      print("[METADATA] Invalid pending metadata update")
      return
    }
    
    // Ensure AVAudioSession is active
    self.configureAudioSession()
    
    // Create metadata dictionary with additional required properties
    var nowPlayingInfo: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: artist,
      MPMediaItemPropertyAlbumTitle: "WPFW 89.3 FM",
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyIsLiveStream: true,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
      MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue
    ]
    
    // Set metadata
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    print("[METADATA] Applied debounced update: \(title) by \(artist), playing=\(isPlaying)")
    
    // Handle artwork if present
    if let artworkUrl = update["artworkUrl"] as? String,
       let url = URL(string: artworkUrl) {
      // Load artwork asynchronously
      URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
        guard let data = data, let image = UIImage(data: data) else { return }
        
        DispatchQueue.main.async {
          // Create artwork
          let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
          
          // Update info with artwork
          if var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            currentInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
            print("[METADATA] Added artwork to lockscreen")
            
            // Verify title is still correct (sometimes it gets overridden)
            let currentTitle = currentInfo[MPMediaItemPropertyTitle] as? String
            if currentTitle != title {
              print("[METADATA] Warning: Title changed during artwork update, fixing...")
              MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
            }
          }
        }
      }.resume()
    }
  }
}
```

## Root Cause Analysis

### 1. Excessive Metadata Updates
- Multiple playback state changes per second (see logs)
- Each state change triggers a metadata update
- Competing update paths between Flutter and native iOS code

### 2. Metadata Flickering Issues
- Metadata alternates between valid data and placeholder text
- just_audio_background interfering with native metadata handling

### 3. Platform-Specific Complications
- iOS-specific audio session configuration problems
- Inconsistent lockscreen metadata display
- UIKit lifecycle warnings

## Latest Fixes Implemented

### 1. Removed Excessive Updates
- Removed `_updateLockscreenOnPlaybackChange` from playback state listener
- Consolidated all metadata updates through a single path

### 2. Enhanced Audio Session Handling
- Added proper lifecycle methods to AppDelegate.swift
- Configured audio session with enhanced options
- Added proper metadata properties for streaming audio

### 3. Improved Metadata Handling
- Added comprehensive placeholder filtering
- Implemented debounce mechanism (250ms)
- Added main thread handling for UI updates

## Remaining Issues

### 1. Flickering During Playback
- Metadata still alternates between valid data and "Not Playing" during playback
- Stable when audio is stopped

### 2. Potential Conflicts
- just_audio_background may still be fighting for control of the lockscreen
- Multiple playback state changes still occurring

## Next Steps

### 1. Potential Solutions to Try
- **Complete Isolation**: Completely disable just_audio_background's metadata handling
- **Native Audio Implementation**: Consider a fully native iOS audio implementation
- **radio_player Plugin**: Explore radio_player plugin as an alternative

### 2. Further Debugging
- Add more forensic logging to track metadata changes during playback
- Monitor lockscreen state changes in real-time
- Test with different iOS versions and devices

## References

### External Resources
- [MPNowPlayingInfoCenter Documentation](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [MPRemoteCommandCenter Documentation](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter)
- [AVAudioSession Configuration](https://developer.apple.com/documentation/avfoundation/avaudiosession)

## Archive Reference Guide

All historical documentation has been archived for reference. Below is a guide to what each archived document contains:

### Core Implementation Documents

1. **[LOCKSCREEN_METADATA_SINGLE_SOURCE.md](/docs/archive/LOCKSCREEN_METADATA_SINGLE_SOURCE.md)**
   - Comprehensive guide with detailed implementation history
   - Contains step-by-step analysis of all attempted solutions
   - Includes code snippets for both Dart and Swift implementations
   - 1400+ lines of detailed documentation

2. **[iOS_LOCKSCREEN_COMPREHENSIVE.md](/docs/archive/iOS_LOCKSCREEN_COMPREHENSIVE.md)**
   - Focuses on the comprehensive solution approach
   - Details the Swift Metadata Guard implementation
   - Contains enhanced remote command handling code
   - Includes channel testing and verification code

3. **[FINAL_ATTEMPT_LOGS_ANALYSIS.md](/docs/archive/FINAL_ATTEMPT_LOGS_ANALYSIS.md)**
   - Detailed analysis of logs from testing sessions
   - Identifies patterns in metadata update failures
   - Contains timestamp correlations between events
   - Useful for forensic debugging of the issue

### Alternative Approaches

1. **[ios-native-audio.md](/docs/archive/ios-native-audio.md)**
   - **CRITICAL REFERENCE**: Complete "Plan B" implementation
   - Detailed architecture for a fully native iOS audio solution
   - Contains full code for NativeAudioManager.swift
   - Includes Flutter-to-native bridge implementation
   - Provides complete integration steps for a hybrid approach

2. **[gemini-fix.md](/docs/archive/gemini-fix.md)**
   - Alternative approach generated by Gemini AI
   - Focuses on isolating just_audio_background conflicts
   - Contains unique insights not covered in other documents

### Supporting Documentation

1. **[iOS_FUNDAMENTAL_ISSUES.md](/docs/archive/iOS_FUNDAMENTAL_ISSUES.md)**
   - Core analysis of fundamental iOS audio session issues
   - Explains iOS-specific audio lifecycle management
   - Contains background mode configuration details

2. **[LOCKSCREEN_FIX_IMPLEMENTATION_LOG.md](/docs/archive/LOCKSCREEN_FIX_IMPLEMENTATION_LOG.md)**
   - Chronological log of implementation attempts
   - Contains notes on what worked and what failed
   - Useful for understanding the evolution of the solution

3. **[LOCKSCREEN_FIX_VERIFICATION.md](/docs/archive/LOCKSCREEN_FIX_VERIFICATION.md)**
   - Test cases and verification procedures
   - Contains specific steps to reproduce and verify fixes
   - Includes edge case scenarios to test

4. **[NEXT_STEPS_LOCKSCREEN_FIX.md](/docs/archive/NEXT_STEPS_LOCKSCREEN_FIX.md)**
   - Prioritized list of next steps from previous analysis
   - Contains specific action items for further development
   - Includes decision points for alternative approaches
