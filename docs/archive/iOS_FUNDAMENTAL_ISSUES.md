# Fundamental iOS Lockscreen Issues - Analysis and Approach

## Overview

This document catalogs the fundamental issues we've identified in the iOS lockscreen metadata implementation for the WPFW Radio app, based on extensive testing and log analysis.

## Core Issues Identified

### 1. AVAudioSession Configuration Errors

```
[AUDIO] Attempting to set AVAudioSession category to .playback
AVAudioSessionClient_Common.mm:597 Failed to set properties, error: -50
[AUDIO][ERROR] Failed to set category: Error Domain=NSOSStatusErrorDomain Code=-50 "(null)"
```

This error code (-50) appears consistently in our logs and indicates a fundamental issue with audio session configuration. According to Apple documentation, error code -50 represents `paramErr` - a parameter error in the audio session configuration.

**Potential Causes:**
- Audio session being configured in multiple places simultaneously (Flutter and native)
- Rapid successive attempts to change audio session category/options
- Conflicting settings between Flutter plugins and native code
- Attempting to set properties while the session is in use

**Supporting Evidence:**
- This error appears even when our metadata is successfully displaying on the lockscreen
- Error frequency increases when both Flutter audio handler and native Swift code attempt to configure the session
- It occurs with specific timing related to metadata updates

### 2. Competing Metadata Sources

```
[FORENSIC][OVERRIDE] Detected metadata override by just_audio_background!
[FORENSIC][OVERRIDE] Expected: 'WPFW 89.3 FM' by 'Jazz and Justice Radio'
[FORENSIC][OVERRIDE] Current: 'WPFW Radio' by 'WPFW'
```

Despite our attempts to disable just_audio_background's metadata control, it continues to override our metadata.

**Battle Pattern Observed:**
1. Our Swift code sets metadata correctly
2. just_audio_background overrides it with default values
3. Our guard detects this and restores our metadata
4. just_audio_background overrides it again
5. Cycle repeats indefinitely, causing visible flickering on the lockscreen

**Supporting Evidence:**
- Logs show this pattern occurring multiple times per second
- The flickering is visible on the lockscreen as metadata changes between correct values and default values
- Our metadata guard timer correctly detects and tries to fix the issue, but can't prevent the initial override

### 3. Excessive Metadata Update Frequency

```
flutter: INFO: 2025-04-18 19:51:25.908561: WPFWRadio: 🎵 Playback state changed: playing=true, updating lockscreen
flutter: INFO: 2025-04-18 19:51:25.908752: WPFWRadio: 🔒 Sending real metadata to iOS lockscreen: title="Robyn's Place", artist="Playing: When I Give My Love (This Time) (Remastered) - Phyllis Hyman", isPlaying=true
flutter: INFO: 2025-04-18 19:51:25.909034: WPFWRadio: 🔒 NATIVE: Throttling metadata update (last update 3s ago)
```

The Flutter layer is generating metadata updates at an extremely high frequency, often multiple times per second.

**Issues:**
- Overwhelming the native layer with update requests
- Potentially destabilizing the MPNowPlayingInfoCenter
- Increasing likelihood of race conditions between competing systems
- Consuming excessive system resources

**Supporting Evidence:**
- Logs show metadata update attempts occurring 10+ times per second
- Our throttling mechanism is preventing most updates from being sent to iOS
- Even with throttling, the update frequency remains high

### 4. Plugin Version Conflicts

```
just_audio 0.9.46 (0.10.0 available)
just_audio_background 0.0.1-beta.15 (0.0.1-beta.16 available)
```

We're using slightly older versions of the audio plugins, and several StackOverflow solutions specifically mention version-specific fixes.

**Considerations:**
- Newer versions might have fixed iOS-specific metadata handling
- Beta status of just_audio_background suggests potential stability issues
- Version interactions between the plugins may be problematic

### 5. Initialization Order Problems

Analysis of our logs reveals potential initialization order issues:

1. AVAudioSession is being configured before Flutter is fully initialized
2. just_audio_background is initializing and taking control before our native code
3. Metadata is being sent before the audio session is correctly configured
4. Remote commands are registered before platform channels are fully established

**Supporting Evidence:**
- Errors in logs showing specific sequence of events
- Occasional initialization errors when starting the app
- Inconsistent behavior between app restarts

## StackOverflow Solutions That Worked For Others

Research shows that several approaches have successfully resolved similar issues in other apps:

### 1. Proper AVAudioSession Configuration

From [iOS remote commands not working with Flutter just_audio](https://stackoverflow.com/questions/72346039/flutter-ios-using-just-audio-with-background-play-remote-commands-not-working):

```swift
// Correct AVAudioSession configuration approach
let audioSession = AVAudioSession.sharedInstance()
do {
    try audioSession.setCategory(.playback, mode: .default)
    try audioSession.setActive(true)
} catch {
    print("Failed to set audio session category: \(error)")
}
```

Key points:
- Configure once at app startup
- Use `.playback` category consistently
- Set active once, not repeatedly
- Handle errors appropriately

### 2. Simplified Plugin Architecture

From [Flutter lockscreen metadata and controls not showing on iOS](https://stackoverflow.com/questions/60104140/flutter-just-audio-background-controls-not-showing-in-ios-lock-screen):

```dart
// Use just_audio without just_audio_background
final player = AudioPlayer();
// Handle metadata natively instead
```

Key points:
- Eliminate competing metadata sources
- Use native iOS code for lockscreen integration
- Single source of truth for metadata

### 3. Proper Info.plist Configuration

From [MPNowPlayingInfoCenter metadata not showing on iOS lockscreen](https://stackoverflow.com/questions/62074810/flutter-audio-player-mpnowplayinginfocenter-not-showing-metadata-on-ios-lockscr):

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Key points:
- Ensure background audio mode is enabled
- Verify required permissions and entitlements
- Check Info.plist configuration

## Targeted Approach Based on Successful Implementations

Based on our analysis and successful StackOverflow solutions, we propose these specific fixes:

### 1. Fix AVAudioSession Configuration

**Implementation:**
```swift
// CRITICAL FIX: Configure AVAudioSession ONCE at app startup
func configureAudioSession() {
    print("[AUDIO] Attempting to configure AVAudioSession")
    let session = AVAudioSession.sharedInstance()
    do {
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        print("[AUDIO] AVAudioSession configured successfully")
    } catch {
        print("[AUDIO][ERROR] Failed to configure AVAudioSession: \(error)")
    }
}
```

- Call this function ONCE in AppDelegate's didFinishLaunchingWithOptions
- Remove ALL other AVAudioSession configuration from the codebase
- Add debugging to verify it's only called once

### 2. Simplify Plugin Architecture

**Implementation:**
1. Remove just_audio_background dependency
2. Use only just_audio for audio playback
3. Implement ALL metadata handling in native Swift
4. Create a single, clear pathway for metadata updates

```dart
// CRITICAL FIX: Remove just_audio_background integration
// Replace with direct just_audio usage
final player = AudioPlayer();
// Use platform channel for metadata
```

### 3. Ensure Correct Initialization Order

**Implementation:**
1. Configure AVAudioSession first, before any Flutter initialization
2. Initialize platform channels BEFORE registering remote commands
3. Set up MPNowPlayingInfoCenter with default values immediately
4. Ensure all components are ready before allowing metadata updates

```swift
// CRITICAL FIX: Proper initialization sequence
override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // 1. Configure audio session FIRST
    configureAudioSession()
    
    // 2. Set up default metadata
    setupDefaultNowPlayingMetadata()
    
    // 3. Initialize Flutter controller
    let controller = window?.rootViewController as! FlutterViewController
    
    // 4. Set up platform channel
    setupMetadataChannel(controller: controller)
    
    // 5. Register remote commands AFTER channel is ready
    setupRemoteCommandCenter()
    
    // 6. Register Flutter plugins
    GeneratedPluginRegistrant.register(with: self)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

### 4. Throttle and Debounce Metadata Updates

**Implementation:**
```swift
// CRITICAL FIX: Proper metadata debouncing
private var lastMetadataUpdate: Date?
private let minUpdateInterval: TimeInterval = 1.0 // Seconds

func updateMetadata(title: String, artist: String, isPlaying: Bool) {
    let now = Date()
    if let lastUpdate = lastMetadataUpdate, now.timeIntervalSince(lastUpdate) < minUpdateInterval {
        print("[METADATA] Throttling update - too frequent")
        return
    }
    
    // Update metadata
    lastMetadataUpdate = now
    // Rest of implementation
}
```

- Add server-side debouncing in Swift code
- Add client-side throttling in Dart code
- Implement a central queue for metadata updates

## Next Steps

1. **Implement AVAudioSession Fixes**:
   - Consolidate configuration to single location
   - Remove redundant configuration attempts
   - Fix the -50 error

2. **Test Plugin Architecture Changes**:
   - Create branch to test with just_audio only
   - Migrate metadata handling to native Swift
   - Test with physical device

3. **Correct Initialization Order**:
   - Restructure AppDelegate
   - Implement proper sequence diagram
   - Add logging to verify order

4. **Verify Implementation**:
   - Test on physical iOS device
   - Debug with forensic logging
   - Verify stable metadata display

## References

1. Apple Documentation:
   - [AVAudioSession Programming Guide](https://developer.apple.com/documentation/avfoundation/avaudiosession)
   - [MPNowPlayingInfoCenter Documentation](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)

2. StackOverflow Solutions:
   - [iOS remote commands not working with Flutter just_audio](https://stackoverflow.com/questions/72346039/flutter-ios-using-just-audio-with-background-play-remote-commands-not-working)
   - [Flutter lockscreen metadata and controls not showing on iOS](https://stackoverflow.com/questions/60104140/flutter-just-audio-background-controls-not-showing-in-ios-lock-screen)
   - [MPNowPlayingInfoCenter metadata not showing on iOS lockscreen](https://stackoverflow.com/questions/62074810/flutter-audio-player-mpnowplayinginfocenter-not-showing-metadata-on-ios-lockscr)

3. Flutter Plugin Documentation:
   - [just_audio Documentation](https://pub.dev/packages/just_audio)
   - [just_audio_background Documentation](https://pub.dev/packages/just_audio_background)
