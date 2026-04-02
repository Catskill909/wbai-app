# [2025-04-18] Gemini Analysis: Simplifying NativeMetadataService for iOS Lockscreen Stability

## 1. Context & Objective

This document details the analysis and resulting fix applied to address persistent iOS lockscreen metadata instability (flickering, reverting to placeholders) in the WPFW Radio app. The objective was to ensure reliable metadata updates by streamlining the communication path between Dart and Swift.

## 2. Code Review Summary (Initial Analysis)

As part of the investigation, the following key files were reviewed:

*   **`lib/data/repositories/stream_repository.dart`**: Confirmed it uses `NativeMetadataService` for updates and includes placeholder guards, particularly in `_updateLockscreenOnPlaybackChange`. The logic triggering updates seemed sound.
*   **`lib/services/metadata_service_native.dart`**: This Dart service handled communication with the native iOS layer via a MethodChannel. **Crucially, it contained complex internal timer logic (`_scheduleRefreshCycle`, `_periodicRefreshIntervals`, `_followupDelay`) designed to periodically resend metadata.**
*   **`ios/Runner/AppDelegate.swift`**: Verified correct setup of the MethodChannel (`com.wpfwfm.radio/metadata`), handling of remote commands invoked from Swift back to Dart, and delegation of metadata updates to `MetadataController`.
*   **`ios/Runner/MetadataController.swift`**: Found this Swift class to be robustly implemented. It included:
    *   Effective debouncing (250ms) to prevent rapid-fire updates.
    *   Strong placeholder metadata checks (filtering "Loading stream...", "Connecting...", etc.).
    *   Asynchronous artwork loading.
    *   Checks for significant changes before updating `MPNowPlayingInfoCenter`.
    *   Ensured updates occurred on the main thread.
    *   Included detailed `AVAudioSession` and playback state forensic logging (added in a related step).

## 3. Problem Identification: Redundant Logic Conflict

The core issue identified was a conflict and redundancy between the Dart and Swift layers:

*   **Dart (`NativeMetadataService`)**: Was proactively *resending* metadata updates based on its own internal timers, even if no new metadata had arrived from the stream source.
*   **Swift (`MetadataController`)**: Was intelligently *debouncing* incoming updates, only processing the latest update after a short quiet period (250ms).

This created a race condition where the Swift layer's correct state could be overwritten by outdated information resent by the Dart timers, explaining the flickering/reverting behavior.

## 4. The Plan (As stated in chat)

The primary fix is to remove the complex, redundant refresh timer logic from `NativeMetadataService.dart`. The Swift layer (`MetadataController.swift`) already handles debouncing and ensures updates happen correctly. We will rely on updates triggered by actual metadata changes (`_metadataService.metadataStream` -> `StreamRepository` -> `NativeMetadataService`) or playback state changes (`_audioHandler.playbackState` -> `StreamRepository` -> `NativeMetadataService`).

## 5. Proposed Code Changes (As stated in chat)

The following edits were proposed to `lib/services/metadata_service_native.dart` to remove the timer-based refresh logic:

```dart
{{ ... }}
// CRITICAL: This must match the channel name in AppDelegate.swift
static const MethodChannel _channel =
    MethodChannel('com.wpfwfm.radio/metadata');

// Reference to the audio handler (must be set externally)
static late WPFWAudioHandler audioHandler;

// Register the MethodCallHandler for remote commands from iOS
static void registerRemoteCommandHandler() {
  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'remotePlay':
        LoggerService.info('🔒 REMOTE COMMAND: Play triggered from iOS lockscreen');
        await audioHandler.play();
        break;
      case 'remotePause':
        LoggerService.info('🔒 REMOTE COMMAND: Pause triggered from iOS lockscreen');
        await audioHandler.pause();
        break;
      case 'remoteToggle':
        LoggerService.info('🔒 REMOTE COMMAND: TogglePlayPause triggered from iOS lockscreen');
        if (audioHandler.playbackState.value.playing) {
          await audioHandler.pause();
        } else {
          await audioHandler.play();
        }
        break;
      default:
        LoggerService.warning('🔒 REMOTE COMMAND: Unknown method ${call.method}');
    }
  });
}

// Track the last metadata update time to avoid too frequent updates
DateTime? _lastUpdateTime;

// // Properly track all active timers for cleanup << REMOVED
// final List<Timer> _refreshTimers = []; << REMOVED

// Store the last metadata parameters for reuse in refresh cycles
String? _lastTitle;
String? _lastArtist;
String? _lastArtworkUrl;
bool _lastPlayingState = false;

// Constants to control refresh behavior
static const Duration _throttleInterval = Duration(seconds: 5);
// static const Duration _followupDelay = Duration(seconds: 3); << REMOVED
// static const List<Duration> _periodicRefreshIntervals = [ << REMOVED
//   Duration(seconds: 30), << REMOVED
//   Duration(minutes: 1), << REMOVED
//   Duration(minutes: 2), << REMOVED
//   Duration(minutes: 5), << REMOVED
// ]; << REMOVED

/// Update the iOS lockscreen with show metadata
Future<bool> updateMetadata({
  required String title,
  required String artist,
  String? artworkUrl,
  bool forceUpdate = false,
  bool isPlaying = true, // CRITICAL: Track playback state
}) async {
  // Only run on iOS
  if (!Platform.isIOS) return false;

  // === BEGIN PLACEHOLDER GUARD ===
  final placeholderTitles = ['Loading stream...', 'Connecting...', '', 'WPFW Radio', 'WPFW Stream'];
  final placeholderArtists = ['Connecting...', '', 'Live Stream'];
  final isPlaceholderTitle = placeholderTitles.contains(title.trim());
  final isPlaceholderArtist = placeholderArtists.contains(artist.trim());
  if (isPlaceholderTitle || isPlaceholderArtist) {
    LoggerService.info('🔒 [BLOCKED] Placeholder metadata blocked from iOS lockscreen update: title="$title", artist="$artist"');
    return false;
  }
  // === END PLACEHOLDER GUARD ===

  // Store metadata for comparison
  // No longer needed for refresh cycles, but kept for _isSignificantMetadataChange check
  _lastTitle = title;
  _lastArtist = artist;
  _lastArtworkUrl = artworkUrl;
  _lastPlayingState = isPlaying;

  // Check if this is a significant metadata change to avoid redundant updates
  final isSignificantChange =
      _isSignificantMetadataChange(title, artist, artworkUrl, isPlaying);

  // Throttle updates unless forced or significant change
  final now = DateTime.now();
  if (!forceUpdate && !isSignificantChange && _lastUpdateTime != null) {
    final difference = now.difference(_lastUpdateTime!);
    if (difference < _throttleInterval) {
      LoggerService.info(
          '🔒 NATIVE: Throttling metadata update (last update ${difference.inSeconds}s ago)');
      // // Only schedule a refresh if we don't already have one planned << REMOVED REFRESH LOGIC
      // if (_refreshTimers.isEmpty) { << REMOVED REFRESH LOGIC
      //   _scheduleRefreshCycle(); << REMOVED REFRESH LOGIC
      // } << REMOVED REFRESH LOGIC
      return true; // Still return true as the update is intentionally throttled
    }
  }
  _lastUpdateTime = now;

  try {
    LoggerService.info('🔒 NATIVE: Updating iOS lockscreen metadata');
    LoggerService.info(
        '🔒 NATIVE: Title="$title", Artist="$artist", IsPlaying=$isPlaying');

    // Ensure we have valid data
    if (title.isEmpty) {
      LoggerService.error('🔒 NATIVE: Empty title provided');
      title = 'WPFW Radio';
    }

    if (artist.isEmpty) {
      LoggerService.error('🔒 NATIVE: Empty artist provided');
      artist = 'Live Stream';
    }

    // Create metadata map with playback state
    final Map<String, dynamic> metadata = {
      'title': title,
      'artist': artist,
      'isPlaying': isPlaying, // CRITICAL: Pass playback state to native code
      // Add forceUpdate flag so Swift knows if it should bypass its cache check
      // Although Swift's debounce might make this less critical
      'forceUpdate': forceUpdate,
    };

    // Add artwork if available
    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      metadata['artworkUrl'] = artworkUrl;
    }

    // Send to native code
    await _channel.invokeMethod('updateMetadata', metadata);
    LoggerService.info('🔒 NATIVE: Lockscreen metadata updated successfully via invokeMethod');

    // // Cancel any existing refresh timers to prevent cascading updates << REMOVED
    // _cancelAllTimers(); << REMOVED

    // // Schedule a single refresh cycle with appropriate intervals << REMOVED
    // _scheduleRefreshCycle(); << REMOVED

    return true;
  } catch (e) {
    LoggerService.error('🔒 NATIVE: Failed to update lockscreen: $e');
    return false;
  }
}

/// Determines if metadata has changed significantly enough to warrant an immediate update
bool _isSignificantMetadataChange(
    String title, String artist, String? artworkUrl, bool isPlaying) {
  // If we've never updated before, it's a significant change
  // Use _lastTitle check as a proxy for first update, as _lastUpdateTime is set after this check
  if (_lastTitle == null) return true;

  // If the playback state has changed, it's significant
  if (_lastPlayingState != isPlaying) return true;

  // If the title or artist has changed, it's significant
  if (_lastTitle != title || _lastArtist != artist) return true;

  // If artwork URL has changed (covers new artwork or artwork removal)
  if (_lastArtworkUrl != artworkUrl) return true;

  // Otherwise, it's not significant enough to bypass throttling
  return false;
}

// // Cancel all active timers to prevent cascading updates << ENTIRE METHOD REMOVED
// void _cancelAllTimers() {
//   for (final timer in _refreshTimers) {
//     if (timer.isActive) {
//       timer.cancel();
//     }
//   }
//   _refreshTimers.clear();
//   LoggerService.info('🔒 NATIVE: Cancelled all refresh timers');
// }

// // Schedule a complete refresh cycle with appropriate intervals << ENTIRE METHOD REMOVED
// void _scheduleRefreshCycle() {
//   if (_lastTitle == null || _lastArtist == null) {
//     LoggerService.error(
//         '🔒 NATIVE: Cannot schedule refresh cycle without metadata');
//     return;
//   }
//
//   LoggerService.info('🔒 NATIVE: Scheduling unified refresh cycle');
//
//   // Schedule a single follow-up update after a short delay
//   Timer followupTimer = Timer(_followupDelay, () {
//     updateMetadata(
//       title: _lastTitle!,
//       artist: _lastArtist!,
//       artworkUrl: _lastArtworkUrl,
//       isPlaying: _lastPlayingState,
//       forceUpdate: true, // Force the follow-up to ensure it goes through
//     );
//   });
//   _refreshTimers.add(followupTimer);
//
//   // Schedule periodic refreshes using the stored intervals
//   for (final interval in _periodicRefreshIntervals) {
//     Timer periodicTimer = Timer(interval, () {
//       updateMetadata(
//         title: _lastTitle!,
//         artist: _lastArtist!,
//         artworkUrl: _lastArtworkUrl,
//         isPlaying: _lastPlayingState,
//         forceUpdate: false, // Periodic refreshes don't need to be forced
//       );
//     });
//     _refreshTimers.add(periodicTimer);
//   }
//
//   LoggerService.info(
//       '🔒 NATIVE: Scheduled ${_refreshTimers.length} refresh timers');
// }

/// Dispose method to clean up resources if needed (though timers are removed)
void dispose() {
  // _cancelAllTimers(); // Ensure timers are cancelled if the service is disposed << REMOVED
  LoggerService.info('🔒 NATIVE: NativeMetadataService disposed');
}
{{ ... }}

```

**(Note:** The diff view shown after the proposal is not included here, just the full code block as it was presented with the `<< REMOVED` annotations indicating the intended changes.)

## 6. Solution Summary (Post-Implementation)

The proposed changes above were applied:
*   The timer-related variables (`_refreshTimers`, `_followupDelay`, `_periodicRefreshIntervals`) were removed.
*   The timer functions (`_scheduleRefreshCycle`, `_cancelAllTimers`) were removed.
*   Calls to these timer functions were removed from `updateMetadata` and `clearMetadata`.
*   `_isSignificantMetadataChange` was updated.

## 7. Expected Outcome

*   Elimination of the Dart/Swift timing conflict.
*   Stable display of correct metadata on the iOS lockscreen without flickering or reverting.
*   Continued correct functioning of lockscreen playback controls.
*   A cleaner, simpler, and more maintainable metadata update pathway.

## 8. Next Steps (Post-Fix)

1.  **Thorough Testing:** Execute various playback scenarios (start, stop, song change, background/foreground, interruptions) on a physical iOS device.
2.  **Analyze Logs:** Monitor Xcode logs, paying close attention to the forensic output from `MetadataController.swift` regarding `AVAudioSession` status, `isPlaying` state, and metadata content received *by Swift*.
3.  **Refine (If Needed):** Adjust Swift debounce timing (`debounceInterval`) or placeholder filters if logs indicate issues. Revisit Dart `StreamRepository` if logs show *incorrect content* being sent to Swift.

## 9. [2025-04-18] Swift Metadata Guard & Enhanced Remote Command Handling

### Problem: Competing Metadata Sources & Non-Functional Remote Controls

Despite our previous fixes, we've encountered two persistent issues:

1. **Metadata Display Issue:** just_audio_background continues to override our Swift-set metadata, causing flickering between correct show metadata and placeholder text
2. **Remote Control Issue:** Lockscreen controls (play/pause) appear but don't control audio playback

### Root Cause Analysis

#### Metadata Display Issue
Forensic logging revealed a clear pattern of metadata overrides:

```
[FORENSIC][VERIFY] Expected: 'WPFW 89.3 FM' by 'Jazz and Justice Radio', rate=1.0
[FORENSIC][VERIFY] Current: 'WPFW Radio' by 'WPFW' rate=1.0
[FORENSIC][RECOVERY] Metadata verification failed - retrying update with force
```

The just_audio_background plugin has a direct pathway to MPNowPlayingInfoCenter that bypasses our dummy MediaItem solution, likely through AVPlayer's own metadata handling.

#### Remote Control Issue
The remote command handlers in AppDelegate.swift were correctly set up to invoke methods on the Flutter channel, but:

1. They lacked proper error handling and result callbacks
2. The Flutter side wasn't properly returning results from the method call handler
3. There was no channel verification mechanism to ensure bidirectional communication

### Solution: Two-Part Approach

#### Part 1: Swift Metadata Guard

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

#### Part 2: Enhanced Remote Command Handling

**Swift Side:**
```swift
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
```

**Flutter Side:**
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
          
        // ... other commands
        
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

### Testing Results

Initial testing shows significant improvement:

1. **Metadata Display:**
   - When first starting the app and pressing play: Still some flickering but improved
   - When pressing stop: Metadata shows correctly (as before)
   - **NEW IMPROVEMENT:** When pressing play again after stopping: Metadata stays visible!

2. **Remote Controls:**
   - Testing in progress for the enhanced remote command handling

### Next Steps

1. **Complete testing** on physical iOS devices to verify both metadata display and remote controls
2. **Monitor logs** for any communication issues between Swift and Flutter
3. **Consider radio_player plugin** as a potential alternative if persistent issues remain

### Technical Notes

This approach represents our most comprehensive solution yet, addressing both the metadata display and remote control aspects of the lockscreen experience. The combination of the Swift Metadata Guard and enhanced remote command handling should provide a stable, reliable user experience while maintaining compatibility with the existing just_audio implementation.
