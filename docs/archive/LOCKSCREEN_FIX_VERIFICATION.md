# iOS Lockscreen Metadata Fix: Verification Guide

## Test Results (April 18, 2025)

After implementing the fixes and testing with a release build, we observed the following issues that still persist:

1. **Artwork Not Showing**: The lockscreen artwork image is not displaying

2. **Metadata Still Flickering During Playback**: When playing, the metadata continues to switch between valid metadata and static text

3. **Better Behavior When Stopped**: When playback is stopped, the correct metadata shows without refreshing

These results indicate we've made progress but still have fundamental issues to resolve.

## Key Changes Implemented

We've implemented a comprehensive fix for the iOS lockscreen metadata instability issues that addresses the fundamental problems identified in our investigation:

### 1. Fixed AVAudioSession Configuration Issues

**Problem:** The iOS audio session was being configured in multiple places, leading to error code -50 and unstable behavior.

**Fix Implemented:**
- Created a single source of truth for AVAudioSession configuration
- Implemented a guard to prevent multiple configurations
- Fixed initialization order so AVAudioSession is configured first
- Added comprehensive logging to track session state

```swift
// CRITICAL FIX: Single source for AVAudioSession configuration
private func configureAudioSession() {
  if audioSessionConfigured {
    print("[AUDIO][FIX] AVAudioSession already configured, skipping")
    return
  }
  
  print("[AUDIO][FIX] Configuring AVAudioSession ONCE at app startup")
  let session = AVAudioSession.sharedInstance()
  do {
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)
    audioSessionConfigured = true
    print("[AUDIO][FIX] AVAudioSession configured successfully")
  } catch {
    print("[AUDIO][FIX][ERROR] Failed to configure AVAudioSession: \(error)")
  }
}
```

### 2. Fixed Remote Command Handling

**Problem:** Remote commands (play/pause/toggle) on the lockscreen were not communicating back to Flutter.

**Fix Implemented:**
- Updated Swift remote command handlers to properly invoke Flutter methods
- Matched method names between Swift and Dart
- Added audio session refresh when commands are received
- Implemented comprehensive error handling

```swift
// Add handler for play command
commandCenter.playCommand.addTarget { [weak self] event in
  print("[REMOTE][FIX] Remote play command received")
  // CRITICAL FIX: Ensure audio session is active immediately when command is received
  self?.configureAudioSession()
  
  DispatchQueue.main.async {
    self?.metadataChannel?.invokeMethod("remotePlay", arguments: nil, result: { result in
      if let error = result as? FlutterError {
        print("[REMOTE][ERROR] Failed to send remotePlay: \(error)")
      } else {
        print("[REMOTE][FIX] Successfully sent remotePlay to Flutter")
      }
    })
  }
  return .success
}
```

### 3. Fixed Metadata Update Throttling

**Problem:** Excessive metadata updates were overwhelming the MPNowPlayingInfoCenter, causing instability.

**Fix Implemented:**
- Added proper debouncing in both Swift and Dart
- Created a keep-alive system to maintain audio session
- Ensured consistent metadata fields required by iOS
- Implemented update throttling with override for significant changes

```swift
// CRITICAL FIX: Debounce updates
let now = Date()
if now.timeIntervalSince(lastMetadataUpdate) < minUpdateInterval {
  print("[METADATA][FIX] Throttling update - too frequent")
  result(true) // Return success but don't update
  return
}
```

### 4. Fixed Initialization Order

**Problem:** Improper initialization order was causing race conditions.

**Fix Implemented:**
- Setup AVAudioSession before Flutter initialization
- Set default metadata immediately
- Initialize platform channels before remote commands
- Added proper sequence validation

```swift
// CRITICAL FIX: Proper initialization order
// 1. Configure AVAudioSession FIRST - before ANY Flutter initialization
configureAudioSession()

// 2. Set up default metadata immediately
setupDefaultMetadata()

// 3. Initialize Flutter controller
// 4. Set up platform channels
// 5. Register for remote control events AFTER channel setup
// 6. Register plugins last
```

### 5. Added Audio Session Keep-Alive

**Problem:** Audio session was becoming inactive over time, especially during background operation.

**Fix Implemented:**
- Added a periodic ping from Flutter to iOS to keep session alive
- Implemented a keep-alive function in Swift that refreshes the session
- Added proper cleanup in dispose method

```dart
// CRITICAL FIX: Periodically ping iOS to keep audio session alive
static void _startAudioSessionKeepAliveTimer() {
  _audioSessionKeepAliveTimer?.cancel();
  _audioSessionKeepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
    _keepAudioSessionAlive();
  });
}
```

## Verification Steps

To verify that the fix has resolved the lockscreen metadata and remote command issues:

1. **Build and Run the App**:
   ```
   cd /Users/paulhenshaw/Desktop/wpfw-app/wpfw_radio
   flutter clean
   flutter pub get
   flutter run --release
   ```

2. **Start Playback**:
   - Launch the app
   - Start the radio stream
   - Verify audio plays normally

3. **Check Lockscreen Metadata**:
   - Lock the iOS device
   - Observe the lockscreen
   - Verify metadata appears correctly without flickering
   - Metadata should show the current show title and artist

4. **Test Remote Commands**:
   - While on the lockscreen, press play/pause
   - Verify playback state changes correctly
   - Verify metadata remains stable
   - Verify remote commands affect playback as expected

5. **Test Durability**:
   - Leave the app running in the background for 10+ minutes
   - Check lockscreen again to verify metadata remains
   - Test remote commands again after extended period

6. **Check Logs for Errors**:
   - Monitor console logs for any error messages
   - No AVAudioSession error codes (-50) should appear
   - No "Failed to send remote command" messages should appear

## Troubleshooting Guide

If issues persist after implementing these fixes:

1. **Audio Session Conflicts**:
   - Check logs for any remaining AVAudioSession error codes
   - Verify no other part of the app is configuring the audio session
   - Check for conflicts with system audio interruptions

2. **Metadata Instability**:
   - Verify metadata is not being updated too frequently
   - Check for placeholder values being set unexpectedly
   - Verify MPNowPlayingInfoCenter contains all required fields

3. **Remote Command Issues**:
   - Verify platform channel names match exactly in Swift and Dart
   - Check method names match exactly
   - Verify commands are being sent to the Flutter side

4. **Background Processing Issues**:
   - Verify background modes are properly set in Info.plist
   - Check for app lifecycle issues affecting audio session
   - Verify keep-alive timer is functioning correctly

## Next Steps Based on Test Results

Based on the test results showing persistent issues, we should implement these additional fixes:

### 1. Fix Artwork Display Issue

The lockscreen artwork is still not appearing. Possible fixes:

```swift
// CRITICAL FIX: Proper artwork handling
private func fetchAndSetArtwork(url: String) {
  guard let artworkUrl = URL(string: url) else { return }
  
  URLSession.shared.dataTask(with: artworkUrl) { [weak self] data, response, error in
    guard let data = data, error == nil else {
      print("[ARTWORK][ERROR] Failed to fetch artwork: \(error?.localizedDescription ?? "Unknown error")")
      return
    }
    
    if let image = UIImage(data: data) {
      // Create MPMediaItemArtwork with image
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
      
      // Update nowPlayingInfo with artwork
      var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
      
      print("[ARTWORK][FIX] Successfully set lockscreen artwork")
    }
  }.resume()
}
```

### 2. Fix Metadata Flickering During Playback

Since metadata continues to flicker, more aggressive protection is needed:

1. **Detect and Block Other Sources**: Add a background observer that detects when other sources change the metadata and immediately reverts it

2. **Root Cause Analysis**: Use the Media Player framework debugging flags to identify exactly what's changing the metadata:

```swift
// Add to didFinishLaunchingWithOptions
if #available(iOS 15.0, *) {
  MPNowPlayingInfoCenter.default()._setDiagnosticMode(true)
}
```

3. **Consider Removal of just_audio_background**: The persistent issues suggest a fundamental conflict with just_audio_background. Consider removing it completely and handling background audio directly.

### 3. More Comprehensive Testing Plan

1. Add tests specifically for these scenarios:
   - Testing with app in foreground vs background
   - Testing different playback states (playing, paused, stopped)
   - Testing metadata updates with varying frequency
   - Testing with and without artwork

2. Create a forensic logging system specifically to track what's changing the metadata and when

### 4. Consider Alternative Implementation

If the issues persist after these fixes, consider one of these alternatives:

1. **radio_player Plugin**: This plugin is specifically designed for radio apps with lockscreen controls

2. **Native iOS Audio Implementation**: Replace just_audio with a fully native Swift implementation using AVPlayer directly

3. **Flutter_sound Plugin**: An alternative to just_audio that some developers report has better iOS lockscreen support

## References

- [Apple AVAudioSession Documentation](https://developer.apple.com/documentation/avfoundation/avaudiosession)
- [MPNowPlayingInfoCenter Documentation](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [Flutter Method Channel Documentation](https://docs.flutter.dev/development/platform-integration/platform-channels)
