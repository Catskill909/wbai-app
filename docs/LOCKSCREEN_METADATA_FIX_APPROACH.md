# iOS Lockscreen Metadata Fix Approach

## ⚠️ DEVELOPMENT GUIDELINES ⚠️

- **FOCUS**: Fix ONLY the specific iOS lockscreen metadata issue
- **MINIMAL CHANGES**: Make targeted modifications to existing files only
- **CONFIRM**: Get explicit approval before any significant changes
- **INCREMENTAL**: Test each small change before proceeding

## Research Findings (2025-04-19)

Based on Reddit and GitHub discussions, we've identified several common issues and solutions for iOS lockscreen metadata with Flutter and just_audio:

## Current Issues

1. **Metadata Display**:
   - Metadata appears on lockscreen when audio is NOT playing
   - Metadata disappears when audio IS playing
   - Cycles between valid metadata and "Not Playing" text

2. **Remote Controls**:
   - Buttons appear but don't control playback
   - No communication between Swift handlers and Flutter audio player

## Common Solutions from Flutter Community

1. **Playback Rate Setting**:
   - Setting the correct `MPNowPlayingInfoPropertyPlaybackRate` is crucial
   - Use 0.0 when paused, 1.0 when playing
   - Many developers report metadata only appears with correct playback rate

2. **Audio Session Configuration**:
   - Ensure proper `AVAudioSession` configuration and activation
   - Keep the audio session active during playback
   - Use `.playback` category with appropriate options

3. **Timing of Metadata Updates**:
   - Add a small delay after starting playback before updating metadata
   - Some developers found that updating metadata immediately after playback state changes works better

4. **Physical Device Testing**:
   - Lockscreen controls might not appear correctly in iOS simulators
   - Always test on physical devices for accurate results

5. **Method Channel Communication**:
   - Ensure bidirectional communication between Flutter and native code
   - Update metadata from Flutter to Swift and handle controls from Swift to Flutter

## Targeted Fix Approach

### 1. AppDelegate.swift Modifications
- Update MPNowPlayingInfoCenter with correct playback rate (1.0 when playing)
- Connect remote command handlers to Flutter method channel
- Ensure audio session configuration is correct and stays active
- Add small delay after playback state changes before updating metadata

### 2. Flutter Method Channel Handling
- Add handlers for remote commands from iOS
- Ensure proper communication with audio player
- Send playback state changes to native code

### 3. Metadata Updates
- Synchronize metadata updates with playback state
- Ensure consistent metadata presence during playback
- Update metadata after playback state changes, not before

## Testing Strategy

- Test each component individually
- Verify lockscreen metadata appears during playback
- Confirm remote controls work properly
- Test different scenarios (play/pause/metadata changes)
- **Important**: Test on physical iOS devices, not just simulators

## Implementation Notes

This approach focuses on fixing the specific issues without architectural changes or rewrites. All modifications will be minimal and targeted to the specific problems identified.

## Current State of Codebase (2025-04-19)

- The codebase has been reset to a clean state with `git reset --hard HEAD` and `git clean -fd`
- Audio playback works but lockscreen metadata is not displaying properly
- The IDE may show some files that no longer exist in the filesystem (like `audio_player_factory.dart`)
- Current files in the services directory:
  - audio_service/wpfw_audio_handler.dart
  - ios_lockscreen_service.dart
  - metadata/lockscreen_service.dart
  - metadata_service.dart
  - metadata_service_native.dart

## Specific Code Changes to Try

1. In AppDelegate.swift:
   ```swift
   // When updating nowPlayingInfo, ensure playback rate is set correctly
   var nowPlayingInfo: [String: Any] = [...]
   nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
   
   // Set metadata on main thread with slight delay after playback state changes
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
       MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
   }
   ```

2. Audio Session Configuration:
   ```swift
   // Configure audio session for background playback
   let session = AVAudioSession.sharedInstance()
   do {
       try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowAirPlay])
       try session.setActive(true, options: .notifyOthersOnDeactivation)
   } catch {
       print("[AUDIO] Session configuration error: \(error)")
   }
   ```

3. Flutter-side metadata updates:
   ```dart
   // Update metadata after playback state changes
   _audioHandler.playbackState.listen((state) {
     if (state.playing && _currentMetadata != null) {
       // Small delay before updating metadata
       Future.delayed(Duration(milliseconds: 500), () {
         _updateLockscreenMetadata(isPlaying: true);
       });
     } else {
       _updateLockscreenMetadata(isPlaying: false);
     }
   });
   ```
