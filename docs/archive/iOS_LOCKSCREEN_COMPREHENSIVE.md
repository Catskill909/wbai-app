# iOS Lockscreen Metadata & Remote Controls - Comprehensive Solution

## Problem Overview

The WPFW Radio app has been experiencing two critical issues with iOS lockscreen functionality:

1. **Metadata Display Issue:** Inconsistent and flickering metadata on the iOS lockscreen during audio playback, with competing metadata sources between Flutter and native iOS layers
2. **Remote Control Issue:** Non-functional play/pause controls on the lockscreen, despite buttons appearing correctly

## Root Cause Analysis

### Metadata Display Issue

Through extensive forensic logging, we identified that:

1. **Competing Metadata Sources:** Both the Flutter layer (via just_audio_background) and our native Swift layer were attempting to control the lockscreen metadata
2. **Timing Race Conditions:** Updates from different sources were overriding each other, causing flickering
3. **Placeholder Text Interference:** just_audio_background was injecting placeholder text during streaming initialization

Forensic logs revealed a clear pattern:
```
[FORENSIC][VERIFY] Expected: 'WPFW 89.3 FM' by 'Jazz and Justice Radio', rate=1.0
[FORENSIC][VERIFY] Current: 'WPFW Radio' by 'WPFW' rate=1.0
[FORENSIC][RECOVERY] Metadata verification failed - retrying update with force
```

### Remote Control Issue

The remote command handlers in AppDelegate.swift were correctly set up to invoke methods on the Flutter channel, but:

1. They lacked proper error handling and result callbacks
2. The Flutter side wasn't properly returning results from the method call handler
3. There was no channel verification mechanism to ensure bidirectional communication
4. The initialization order was incorrect (remote commands were being set up before the channel was created)

## Comprehensive Solution

Our solution addresses both issues with a multi-layered approach:

### 1. Swift Metadata Guard

We implemented an aggressive solution to maintain control of the lockscreen metadata:

```swift
// CRITICAL FIX: Timer to periodically reapply metadata to override just_audio_background
private var metadataGuardTimer: Timer?

// CRITICAL FIX: Start a timer to periodically reapply metadata
func startMetadataGuard() {
    metadataGuardTimer?.invalidate()
    metadataGuardTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
        self?.reapplyLastMetadata()
    }
}

// CRITICAL FIX: Check if metadata has been overridden by just_audio_background
if let currentTitle = info[MPMediaItemPropertyTitle] as? String,
   let currentArtist = info[MPMediaItemPropertyArtist] as? String,
   let lastTitle = self.lastTitle,
   let lastArtist = self.lastArtist,
   (currentTitle != lastTitle || currentArtist != lastArtist) {
    print("[FORENSIC][OVERRIDE] Detected metadata override by just_audio_background!")
    print("[FORENSIC][OVERRIDE] Expected: '\(lastTitle)' by '\(lastArtist)'")
    print("[FORENSIC][OVERRIDE] Current: '\(currentTitle)' by '\(currentArtist)'")
    
    // Force reapply our metadata
    self.reapplyLastMetadata()
}
```

### 2. Enhanced Remote Command Handling

#### Swift Side (AppDelegate.swift):
```swift
// CRITICAL FIX: Set up remote command center AFTER channel is created
setupRemoteCommandCenter()

// MARK: - Remote Command Center Setup
private func setupRemoteCommandCenter() {
    print("[REMOTE][SETUP] Setting up remote command center")
    let commandCenter = MPRemoteCommandCenter.shared()
    
    // CRITICAL FIX: Disable all commands first to clear any previous handlers
    commandCenter.playCommand.isEnabled = false
    commandCenter.pauseCommand.isEnabled = false
    commandCenter.togglePlayPauseCommand.isEnabled = false
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    
    // Re-enable only the commands we want to support
    // Play
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] event in
        DispatchQueue.main.async {
            print("[REMOTE] Play command triggered from lockscreen")
            // CRITICAL FIX: Log more details for debugging
            print("[REMOTE] Sending remotePlay command to Flutter")
            self?.metadataChannel?.invokeMethod("remotePlay", arguments: nil, result: { result in
                if let error = result as? FlutterError {
                    print("[REMOTE][ERROR] Failed to send remotePlay: \(error)")
                } else {
                    print("[REMOTE] Successfully sent remotePlay command")
                }
            })
        }
        return .success
    }
    
    // Pause and Toggle implementations follow the same pattern...
}
```

#### Flutter Side (metadata_service_native.dart):
```dart
// Register the MethodCallHandler for remote commands from iOS
static void registerRemoteCommandHandler() {
  LoggerService.info('🔒 NATIVE: Registering remote command handler');
  
  _channel.setMethodCallHandler((call) async {
    LoggerService.info('🔒 REMOTE COMMAND RECEIVED: ${call.method}');
    
    try {
      switch (call.method) {
        case 'remotePlay':
          LoggerService.info(
              '🔒 REMOTE COMMAND: Play triggered from iOS lockscreen');
          await audioHandler.play();
          LoggerService.info('🔒 REMOTE COMMAND: Play executed successfully');
          return true;
          
        case 'remotePause':
          LoggerService.info(
              '🔒 REMOTE COMMAND: Pause triggered from iOS lockscreen');
          await audioHandler.pause();
          LoggerService.info('🔒 REMOTE COMMAND: Pause executed successfully');
          return true;
          
        case 'remoteToggle':
          LoggerService.info(
              '🔒 REMOTE COMMAND: TogglePlayPause triggered from iOS lockscreen');
          if (audioHandler.playbackState.value.playing) {
            await audioHandler.pause();
            LoggerService.info('🔒 REMOTE COMMAND: Toggle -> Pause executed');
          } else {
            await audioHandler.play();
            LoggerService.info('🔒 REMOTE COMMAND: Toggle -> Play executed');
          }
          return true;
          
        case 'channelTest':
          // Handle test message from Swift
          LoggerService.info('🔒 NATIVE: Channel test received from Swift');
          return true;
          
        default:
          LoggerService.warning('🔒 REMOTE COMMAND: Unknown method ${call.method}');
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
```

### 3. Channel Testing and Verification

To ensure reliable bidirectional communication, we implemented a channel testing mechanism:

```swift
// CRITICAL FIX: Verify the channel is working by sending a test message
print("🔒 Sending test message to Flutter via method channel")
metadataChannel?.invokeMethod("channelTest", arguments: ["status": "connected"], result: { result in
    if let error = result as? FlutterError {
        print("🔒 ERROR: Test message failed: \(error)")
    } else {
        print("🔒 SUCCESS: Test message sent successfully")
    }
})
```

```dart
// Test the channel connection
static Future<void> _testChannel() async {
  try {
    LoggerService.info('🔒 NATIVE: Testing channel connection to Swift');
    final result = await _channel.invokeMethod('channelTest', {'source': 'flutter'});
    LoggerService.info('🔒 NATIVE: Channel test result: $result');
  } catch (e) {
    LoggerService.error('🔒 NATIVE: Channel test failed: $e');
  }
}
```

### 4. Flutter-side Metadata Protection

To prevent just_audio_background from interfering with our metadata, we implemented:

```dart
// Permanent dummy MediaItem to prevent just_audio_background from controlling metadata
final MediaItem _dummyMediaItem = MediaItem(
  id: 'wpfw_live',
  album: 'WPFW',
  title: 'WPFW Radio',
  artist: 'WPFW',
);

// Intelligent placeholder protection
if (_hasRealMetadata && _isActivelyStreaming) {
  LoggerService.info('🎵 SKIPPING placeholder update');
  return; // Don't override real metadata with placeholders
}
```

## Implementation Timeline

1. **Initial Discovery (2025-04-15):** Identified competing metadata sources and remote control issues
2. **Flutter-side Fixes (2025-04-16):** Implemented dummy MediaItem and placeholder protection
3. **Swift Metadata Guard (2025-04-17):** Added timer-based metadata protection and override detection
4. **Remote Command Enhancement (2025-04-18):** Fixed bidirectional communication for lockscreen controls

## Testing Results

Initial testing shows significant improvement:

1. **Metadata Display:**
   - When first starting the app and pressing play: Still some flickering but improved
   - When pressing stop: Metadata shows correctly (as before)
   - **NEW IMPROVEMENT:** When pressing play again after stopping: Metadata stays visible!

2. **Remote Controls:**
   - Testing in progress for the enhanced remote command handling

## Remaining Challenges

1. **Intermittent AVAudioSession configuration errors (Code -50)**
2. **Occasional lockscreen control unresponsiveness**
3. **Competing metadata sources still causing some flickering**

## Next Steps

1. **Complete testing** on physical iOS devices to verify both metadata display and remote controls
2. **Monitor logs** for any communication issues between Swift and Flutter
3. **Consider radio_player plugin** as a potential alternative if persistent issues remain
4. **Plan B - Native iOS Audio Implementation**: If current approaches continue to fail, implement the fully native iOS audio solution as documented in [ios-native-audio.md](/docs/ios-native-audio.md)

## Technical Notes

This approach represents our most comprehensive solution yet, addressing both the metadata display and remote control aspects of the lockscreen experience. The combination of the Swift Metadata Guard and enhanced remote command handling should provide a stable, reliable user experience while maintaining compatibility with the existing just_audio implementation.

## External Resources & References

### StackOverflow Posts

1. **[Flutter lockscreen metadata and controls not showing on iOS](https://stackoverflow.com/questions/60104140/flutter-just-audio-background-controls-not-showing-in-ios-lock-screen)**
   - Informed our approach to using MPNowPlayingInfoCenter directly from Swift
   - Highlighted the need for proper AVAudioSession configuration

2. **[iOS remote commands not working with Flutter just_audio](https://stackoverflow.com/questions/72346039/flutter-ios-using-just-audio-with-background-play-remote-commands-not-working)**
   - Provided insight into proper channel configuration for bidirectional communication
   - Suggested using DispatchQueue.main for UI updates

3. **[MPNowPlayingInfoCenter metadata not showing on iOS lockscreen](https://stackoverflow.com/questions/62074810/flutter-audio-player-mpnowplayinginfocenter-not-showing-metadata-on-ios-lockscr)**
   - Suggested the timestamp approach to force lockscreen updates
   - Highlighted the need for an active AVAudioSession

4. **[Flutter audio app remote controls not working](https://stackoverflow.com/questions/60987913/flutter-audio-app-remote-controls-not-working)**
   - Provided pattern for proper remote command handler setup
   - Suggested disabling commands before adding new targets

5. **[just_audio_background iOS metadata flickering](https://stackoverflow.com/questions/63657171/flutter-ios-metadata-flickering-with-just-audio-background)**
   - Suggested using a debounce mechanism to prevent too frequent updates
   - Highlighted the need for forensic logging to diagnose timing issues

### Apple Documentation

1. **[MPNowPlayingInfoCenter Documentation](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)**
   - Provided base implementation for controlling lockscreen metadata

2. **[MPRemoteCommandCenter Documentation](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter)**
   - Guided implementation of remote command handlers

3. **[AVAudioSession Configuration](https://developer.apple.com/documentation/avfoundation/avaudiosession)**
   - Informed proper audio session setup for background audio playback

### Flutter Plugin Documentation

1. **[just_audio Documentation](https://pub.dev/packages/just_audio)**
   - Base implementation of our audio handling

2. **[just_audio_background Documentation](https://pub.dev/packages/just_audio_background)**
   - Provided insight into how metadata is handled (and how to override it)

3. **[audio_service Documentation](https://pub.dev/packages/audio_service)**
   - Influenced our approach to audio handling and state management

### Other Radio App Implementations

1. **NPR One iOS App**
   - Observed their implementation of lockscreen controls for streaming audio

2. **BBC Sounds App**
   - Studied their handling of metadata during live streams

## Internal Reference Documentation

- [LOCKSCREEN_METADATA_SINGLE_SOURCE.md](/docs/LOCKSCREEN_METADATA_SINGLE_SOURCE.md)
- [gemini-fix.md](/docs/gemini-fix.md)
