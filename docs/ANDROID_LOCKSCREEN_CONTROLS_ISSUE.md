# Android Lockscreen & Notification Audio Controls: Investigation & Root Cause Analysis

## Background
The WPFW Radio app previously supported lockscreen and notification audio controls on Android. Recent changes focused on fixing iOS lockscreen metadata issues have inadvertently broken these controls on Android. This document details the investigation, findings, and next steps required to restore Android lockscreen and notification audio controls.

---

## 1. Symptom
- Android lockscreen and status bar audio controls are missing.
- Audio streaming and metadata otherwise work as expected on Android.

---

## 2. Investigation Summary
### Codebase Analysis
- The app uses a "dummy MediaItem" strategy in `WPFWAudioHandler` to block just_audio_background from controlling the lockscreen. This was implemented to enable a native iOS lockscreen metadata solution.
- All real metadata updates to the MediaItem (title, artist, artwork) are intentionally blocked or replaced with a static dummy item.
- This strategy is applied globally, with no platform-specific logic for Android.
- As a result, Android's notification and lockscreen controls (which rely on real MediaItem updates) are never shown or updated with current metadata.

### Plugin & Notification Handling
- The app uses `audio_service` and/or `just_audio`/`radio_player` for audio playback.
- On Android, lockscreen and notification controls are managed by the MediaSession and foreground notification, which require MediaItem updates.
- By always sending a dummy MediaItem and blocking real updates, these controls are disabled on Android.

### Manifest/Config
- The AndroidManifest.xml was not found in the default location, but the app runs, so it must exist elsewhere. The main issue is in the Dart logic, not the manifest.

---

## 3. Root Cause
- The "iOS single source of truth" and "block all MediaItem updates" approach disables Android lockscreen/notification controls because Android relies on those MediaItem updates.
- There is no platform-specific logic to allow MediaItem/notification updates on Android while blocking them on iOS.

---

## 4. Next Steps for a Fix (Planning)
1. **Refactor audio handler logic:**
   - On iOS: Continue blocking MediaItem updates and use the Swift/native channel for lockscreen metadata.
   - On Android: Allow normal MediaItem updates so that notifications and lockscreen controls work as intended.
2. **Ensure MediaItem updates on Android:**
   - On Android, update the MediaItem with real metadata (title, artist, artwork, etc.) as the show/track changes.
3. **Confirm AndroidManifest setup:**
   - Ensure notification channel and foreground service declarations are present (usually handled by the plugin).
4. **Test on a real Android device:**
   - Verify media notification and lockscreen controls appear and function as expected.

---

## 5. Summary
- The missing Android controls are a side effect of the global "block MediaItem updates" strategy introduced for iOS.
- The fix will require platform-specific handling: block updates only on iOS, allow them on Android.

---

**Document prepared: May 7, 2025**
