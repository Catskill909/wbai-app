# iOS UIScene Lifecycle Migration — Notes & Findings

**Status:** Migration was implemented, broke the lock-screen now-playing, and has been **reverted** (Jun 17, 2026). The app is back to its known-working state. The UIScene build warning returns, but it is **non-fatal** — the app builds, installs, and runs.

This document records everything we learned so the next attempt isn't wasted effort.

---

## 1. Why we attempted the migration

Flutter 3.38+ prints this warning on `flutter run`/`flutter build ios`:

> To ensure your app continues to launch on upcoming iOS versions, UIScene lifecycle support will soon be required. Please see https://flutter.dev/to/uiscene-migration for the migration guide.

Per Apple + Flutter docs, UIScene only becomes **mandatory in the release *following* iOS 26**. As of this writing it is just a warning. We are **not** under hard time pressure to migrate.

- Flutter guide: https://docs.flutter.dev/release/breaking-changes/uiscenedelegate
- Source MD: https://github.com/flutter/website/blob/main/src/content/release/breaking-changes/uiscenedelegate.md

---

## 2. What the migration changed (the 4 edits)

These are the exact changes that were made, then reverted. Use this as the recipe for the next attempt.

### a. `ios/Runner/Info.plist` — add scene manifest
```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>UIWindowScene</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
                <key>UISceneConfigurationName</key>
                <string>flutter</string>
                <key>UISceneStoryboardFile</key>
                <string>Main</string>
            </dict>
        </array>
    </dict>
</dict>
```

### b. `ios/Runner/AppDelegate.swift` — adopt `FlutterImplicitEngineDelegate`
- Change class to `FlutterAppDelegate, FlutterImplicitEngineDelegate`.
- Move plugin registration + method channels + `setupRemoteCommandCenter()` out of `didFinishLaunchingWithOptions` and into:
  ```swift
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
      let messenger = engineBridge.applicationRegistrar.messenger()
      // ... create channels, set handlers ...
      setupRemoteCommandCenter()
      GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
  ```
- `didFinishLaunchingWithOptions` keeps only `configureAudioSession()`.
- Remove `applicationDidBecomeActive` (deprecated under UIScene); the equivalent must be done in the SceneDelegate.

### c. `ios/Runner/SceneDelegate.swift` — new file
```swift
import UIKit
import Flutter

@objc class SceneDelegate: FlutterSceneDelegate {
    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        (UIApplication.shared.delegate as? AppDelegate)?.refreshNowPlayingMetadata()
    }
}
```

### d. `ios/Runner.xcodeproj/project.pbxproj` — register `SceneDelegate.swift`
Four entries needed: `PBXBuildFile`, `PBXFileReference`, the `Runner` `PBXGroup` children, and the `Sources` `PBXSourcesBuildPhase` files list.

> Tip for next time: instead of hand-editing `project.pbxproj`, add the file via Xcode (File ▸ New) so the references are generated correctly.

---

## 3. The regression it caused

After migrating: audio played in the background and the lock screen showed correct art + metadata, **but** pressing **pause then play** on the lock screen showed **the previous app's now-playing metadata for a few seconds**, then switched to ours. Confirmed reproducible on a physical iPhone (iPhone 18,1, iOS 26.5.1) with clean uninstall + release reinstall. This did **not** happen before the migration.

---

## 4. Root-cause analysis (what we ruled in/out)

### Architecture facts established
- The lock screen now-playing is driven **entirely by `audio_service`** via `mediaItem.add(...)` → `MPNowPlayingInfoCenter` (see `audio_service`'s `AudioServicePlugin.m` → `updateNowPlayingInfo`).
- The app's **custom Swift channels are dead code for updates**: `com.wbaifm.radio/metadata` (`updateLockscreenMetadata`) and `com.wbaifm.radio/now_playing` (`updateNowPlaying`) are **never called** in production. Only `clearNowPlaying` is used (in `StreamRepository`). So `AppDelegate`'s cached `lastTitle`/`cachedArtwork` are essentially unused at runtime.
- Lock-screen play/pause: `AppDelegate.setupRemoteCommandCenter()` forwards `remotePlay`/`remotePause`/`remoteTogglePlayPause` to Dart via the metadata channel → `NativeMetadataService` → `StreamRepository.play()/pause()`. `audio_service` *also* installs its own command targets when playback starts.

### Where the gap comes from (the mechanism)
- On pause (lock screen → `repo.pause()` → `WBAIAudioHandler.stop()`): `stop()` calls `session.setActive(false)` and `mediaItem.add(null)` (see `wbai_audio_handler.dart`), relinquishing now-playing.
- On play (`repo.play()`): a network **health check** + **M3U resolve** + **buffering** run for several seconds before `_broadcastState` re-asserts `mediaItem`. During that window `MPNowPlayingInfoCenter` is empty, so iOS shows the **last other app** that had now-playing info.

### Why it's a *migration* regression (and not just pre-existing)
- The Dart audio code is **byte-for-byte identical** before/after the migration. Only native scene wiring changed.
- Therefore the regression is the **UIScene lifecycle changing app/engine startup and the lock-screen now-playing handoff timing**. The exact OS/engine-level reason was not pinned down, but the trigger is clearly the scene adoption.

### Things tried that did NOT fix it
1. **Dart `restoreNowPlaying()`** (kept in code, see §6) — re-asserts `mediaItem` at the very top of `repo.play()` before the health check. Helps in theory but did not eliminate the flash under UIScene.
2. **Reordering `setupRemoteCommandCenter()` before `GeneratedPluginRegistrant.register(...)`** in `didInitializeImplicitFlutterEngine` (to stop our `removeTarget(nil)` from wiping `audio_service`'s command handlers). On analysis this is a no-op: both old and new code run before `AudioService.init()` in Dart `main()`, so the relative ordering with `audio_service`'s command-center activation is unchanged. Did not fix it.

---

## 5. Key research finding (the blocker)

- **`audio_service` is at `0.18.18`, the latest release (~14 months old), and has NO UIScene support.** There is no newer version and no published fix.
- Its iOS plugin (`AudioServicePlugin.m`) does not touch the app delegate/window/scene lifecycle — it only uses method channels + `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` + `AVAudioSession`. So we cannot fix the handoff with a simple plugin bump.
- Conclusion: a reliable fix requires either (a) `audio_service` shipping UIScene support, or (b) a non-trivial native workaround to keep our app as the "Now Playing" app across the pause→play gap.

Installed audio versions (from `pubspec.lock`):
- `audio_service: 0.18.18`
- `audio_session: 0.1.25`
- `just_audio: 0.9.46`

---

## 6. Dart change KEPT after revert (harmless, defensive)

`restoreNowPlaying()` was added and left in place — it is platform-agnostic and does no harm:

- `lib/services/audio_service/wbai_audio_handler.dart` — new method:
  ```dart
  void restoreNowPlaying() {
    if (_currentMediaItem != null && _currentMediaItem!.title != "WBAI 99.5 FM") {
      mediaItem.add(_currentMediaItem);
    }
  }
  ```
- `lib/data/repositories/stream_repository.dart` — first line of `play()` calls `_audioHandler.restoreNowPlaying();`.

If a future maintainer wants a pure revert, these two can be removed, but they are safe to keep.

> Note: `ios/Runner/Info.plist` also had a **duplicate `UIBackgroundModes` key** removed during this work. That cleanup was kept (it is unrelated to UIScene and correct).

---

## 7. Recommendations for the next migration attempt

1. **Wait for `audio_service` UIScene support.** Watch the repo: https://github.com/ryanheise/audio_service (issues/releases). Re-migrate once a release adds scene-lifecycle support, or pin a fork that does.
2. When re-attempting, **re-apply the 4 edits in §2** (preferably adding `SceneDelegate.swift` through Xcode, not by hand-editing pbxproj).
3. **Test specifically:** lock screen → pause → play, several times, on a physical device with a release build, after a clean uninstall. Watch for the previous-app metadata flash.
4. If the flash persists, consider a native workaround: keep our app as the Now Playing app across pause by **not** fully relinquishing the audio session / now-playing on pause (e.g. set a paused `MPNowPlayingInfoPropertyPlaybackRate = 0` and keep `nowPlayingInfo` populated) instead of `mediaItem.add(null)` + `session.setActive(false)` in `WBAIAudioHandler.stop()`. This is a behavioral change to the live-stream pause flow and must be tested carefully.
5. Alternatively, evaluate migrating off `audio_service` if it remains unmaintained.

---

## 8. Reference links

- Flutter UIScene migration guide: https://docs.flutter.dev/release/breaking-changes/uiscenedelegate
- "Flutter 3.38 Broke My iOS App": https://medium.com/top-rail/flutter-3-38-broke-my-ios-app-heres-how-i-fixed-it-and-what-apple-didn-t-tell-you-e79c777201c7
- audio_service: https://pub.dev/packages/audio_service  •  repo: https://github.com/ryanheise/audio_service
- Related now-playing staleness discussion: https://github.com/ryanheise/audio_service/issues/1153
