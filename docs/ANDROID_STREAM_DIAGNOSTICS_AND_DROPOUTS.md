# Android Audio Stream Dropouts: Diagnostics & Investigation Plan

## Background
On Android devices, users have reported that the audio stream sometimes drops or stops unexpectedly, requiring a manual restart of the stream. The cause is currently unknown and not visible from user-facing errors.

---

## 1. Problem Statement
- Audio stream drops or stops on Android, requiring user intervention to restart.
- No clear error message or cause is currently logged or surfaced.

---

## 2. Diagnostics & Investigation Strategy

### A. Enhanced Logging
- Add detailed logging in the audio handler and stream repository for:
  - Player state changes (idle, loading, buffering, ready, completed)
  - Errors from the audio player (exceptions, onPlayerError, etc.)
  - Network state changes (if possible)
  - Automatic reconnect attempts and their outcomes

### B. Android Lifecycle & Service Events
- Log Android lifecycle events (`onPause`, `onStop`, `onResume`) if accessible, to see if drops correlate with app backgrounding or interruptions.
- Log foreground service status (if using `audio_service`).

### C. Diagnostics UI (Optional)
- Optionally, surface the last error or player state in a debug overlay or log screen for easier field testing.

### D. Testing
- Run the app on a real Android device.
- Reproduce the stream dropout and capture logs for analysis.
- Look for patterns: network drops, player/plugin errors, lifecycle events, or service interruptions.

---

## 3. Next Steps
1. Audit and improve logging in `WPFWAudioHandler` and related classes.
2. Add logs for all critical events and errors.
3. Test on real device and capture logs after a stream drop.
4. Analyze logs for root cause and plan a fix.
5. Optionally, test fixes alongside the lockscreen controls issue for a comprehensive Android audio experience.

---

**Document prepared: May 7, 2025**
