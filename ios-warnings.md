# iOS Build Warnings: Categorized Action Plan

This document categorizes iOS build warnings by fixability and provides actionable steps. **No app code will be changed** until further review.

---

## 1. Simple Fixes (You/Your Team Can Do in Xcode)

### App Icon Set Has Unassigned Children
- **Warning:** `Assets.xcassets: The app icon set "AppIcon" has 6 unassigned children.`
- **Action:** 
  1. Open `ios/Runner/Assets.xcassets` in Xcode
  2. Select `AppIcon`
  3. Either fill in missing icon slots or remove unassigned ones
- **Reference:** [Stack Overflow](https://stackoverflow.com/questions/35320432/the-app-icon-set-appicon-has-an-unassigned-child)

---

## 2. Warnings Requiring Package Updates

### audio_service: Deprecated API Usage
- **Warning:** `'initWithImage:' is deprecated: first deprecated in iOS 10.0`
- **File:** `AudioServicePlugin.m:213`
- **Action:** 
  - Monitor [audio_service](https://pub.dev/packages/audio_service) for updates
  - Consider opening an issue if not already reported

### flutter_inappwebview_ios: Multiple Deprecations
- **Files:** Multiple files with various deprecations
- **Key Issues:**
  - `spotlightSuggestion` → Use `lookupSuggestion`
  - `clearCache` → Use `InAppWebViewManager.clearAllCache`
  - `SFAuthenticationSession` → Use `ASWebAuthenticationSession`
- **Action:** 
  - Track [flutter_inappwebview issues](https://github.com/pichillilorenzo/flutter_inappwebview/issues)
  - Consider updating to latest version if available

### radio_player: Optional Handling
- **Warning:** `Coercion of implicitly unwrappable value of type 'String?' to 'Any' does not unwrap optional`
- **File:** `RadioPlayer.swift:23`
- **Action:** 
  - Monitor [radio_player](https://pub.dev/packages/radio_player) for updates
  - Consider submitting a PR with proper optional handling

---

## 3. Safe to Ignore (Monitor Only)

### Duplicate Libraries
- **Warning:** `Ignoring duplicate libraries: '-lswiftCoreGraphics'`
- **Why Safe?** Common in Xcode 15+, doesn't affect functionality
- **Reference:** [Xcode 15 Duplicate Library Warnings](https://indiestack.com/2023/10/xcode-15-duplicate-library-linker-warnings/)

### flutter_native_splash Privacy File
- **Warning:** `No rule to process file 'PrivacyInfo.xcprivacy' for architecture 'arm64'`
- **Why Safe?** Known issue with some Flutter plugins
- **Reference:** [GitHub Issue](https://github.com/fluttercommunity/flutter_native_splash/issues/624)

### Storyboard Version Mismatch
- **Warning:** `This file is set to build for a version older than the deployment target`
- **Why Safe?** Only affects build logs, not runtime behavior

---

## Action Plan

### Immediate Actions (Do Now)
1. [ ] Fix AppIcon unassigned children in Xcode

### Monitoring (Check Periodically)
1. [ ] Subscribe to issue trackers for affected plugins
2. [ ] Review release notes for plugin updates

### Future Considerations
1. [ ] If any warning becomes critical, consider forking and patching the plugin
2. [ ] Re-evaluate plugin choices if maintenance becomes an issue

---

*Last Updated: 2025-08-07*
*Note: This document is for tracking purposes. No app code changes should be made without proper testing.*
