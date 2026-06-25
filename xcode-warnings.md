# Xcode Build Warnings — Analysis

Triage of warnings from the Runner archive build. Categorized as **Easy Wins** (fix in our
own project), **Needs Work** (our config, but requires testing), and **Leave Alone** (lives
inside third-party plugin source — wait for the upstream maintainer).

---

## ✅ Easy Wins (our code, low risk)

### 1. Runner — "All interface orientations must be supported unless the app requires full screen"
- **Source:** `ios/Runner/Info.plist` — app is locked to portrait only (iPhone + iPad).
- **Cause:** When an app doesn't support all orientations, Xcode expects `UIRequiresFullScreen`
  to be set so the system knows the app isn't a multitasking/Slide-Over candidate.
- **Fix:** Add to `Info.plist`:
  ```xml
  <key>UIRequiresFullScreen</key>
  <true/>
  ```
- **Risk:** None for a portrait-locked radio app.

---

## 🔧 Needs Work (our config, requires verification)

### 2. flutter_native_splash privacy bundle / Pods — deployment target 9.0
- **Warning:** `Pods.xcodeproj ... IPHONEOS_DEPLOYMENT_TARGET is set to 9.0, but supported
  range is 12.0 to 26.5.99`
- **Source:** Generated Pods project, not plugin source — so we *can* influence it.
- **Cause:** Our `Podfile` has `platform :ios, '13.0'` commented out, so CocoaPods falls back
  to old defaults for resource-bundle targets.
- **Fix:** Uncomment / set `platform :ios, '13.0'` in `ios/Podfile`, then add a `post_install`
  hook to force every Pod target's deployment target:
  ```ruby
  post_install do |installer|
    installer.pods_project.targets.each do |target|
      flutter_additional_ios_build_settings(target)
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      end
    end
  end
  ```
- **Then:** `pod install` and re-archive.
- **Risk:** Low, but requires a clean build + smoke test of all plugins.

---

## 🚫 Leave Alone (third-party plugin source — upstream's job)

These are all deprecation/API warnings inside `~/.pub-cache/` plugin sources or vendored Pods.
We do **not** edit pub-cache — changes are wiped on `pub get` and break reproducible builds.
Track upstream releases and bump the dependency when fixed.

### audio_service (0.18.18)
- `AudioServicePlugin.m:213` — `initWithImage:` deprecated since iOS 10.
- **Action:** None. Cosmetic; still functional. Watch for a newer `audio_service`.

### flutter_inappwebview_ios (1.2.0-beta.3)
The bulk of the warnings. All inside plugin source. Notable ones:
- `keyWindow` deprecated (iOS 13) — multiple files.
- `spotlightSuggestion`, `selectionGranularity`, `WKSelectionGranularity` deprecated (iOS 10/11).
- `clearCache` / `clearCache()` deprecated — internal plugin API rename.
- `SecTrustEvaluate` deprecated (iOS 13).
- `SFAuthenticationSession` deprecated (iOS 12).
- `init(url:entersReaderIfAvailable:)` deprecated (iOS 11).
- `onFindResultReceived(...)` deprecated.
- WebView.storyboard — "set to build for a version older than the deployment target."
- `URLCredential.swift:14` — "Comparing non-optional `[Any]` to nil always returns true" (a
  real upstream bug, but theirs to fix).
- `WebAuthenticationSession.swift:37` — "Unnecessary check for 'iOS'".
- **Action:** None. We're on a **beta** (`1.2.0-beta.3`). Upgrade to a stable `1.2.x`/`1.3.x`
  release when available; do not patch pub-cache.

### share_plus (10.1.4)
- `FPPSharePlusPlugin.m:25` — `keyWindow` deprecated (iOS 13).
- **Action:** None. Bump `share_plus` when upstream addresses it.

### swift-collections (vendored Pod, Flutter dependency)
- `Deque+Collection.swift:26` — non-Sendable `_Storage` in a Sendable struct; "error in Swift 6
  language mode."
- **Action:** None. Transitive dependency pulled in by Flutter tooling. Only becomes a hard
  error if/when the project opts into the Swift 6 language mode, which we are not. Resolves when
  Flutter updates its pinned swift-collections.

---

## Summary

| Warning | Owner | Action |
|---|---|---|
| Interface orientations | Us (Info.plist) | Add `UIRequiresFullScreen` ✅ |
| Pods deployment target 9.0 | Us (Podfile) | Set `platform :ios, '13.0'` + post_install 🔧 |
| audio_service deprecation | Plugin | Leave / track upstream |
| flutter_inappwebview_ios (all) | Plugin (beta) | Leave / upgrade off beta |
| share_plus keyWindow | Plugin | Leave / track upstream |
| swift-collections Sendable | Flutter dep | Leave / harmless unless Swift 6 mode |
