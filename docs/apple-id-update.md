# iOS Bundle Identifier Update Plan
## From `app.pacifica.kpfk` to `com.pacifica.kpfk`

**Date:** November 17, 2025  
**Objective:** Update all references to the iOS bundle identifier to resolve Apple Developer signing issues.

---

## 🔍 Analysis Summary

### Current State
- **Current iOS Bundle ID:** `app.pacifica.kpfk` (unavailable/already registered)
- **Target iOS Bundle ID:** `com.pacifica.kpfk`
- **Android Package:** `app.pacifica.kpfk` (will remain unchanged for Android)
- **Info.plist shows:** `com.pacifica.wpfw` (WPFW app - needs correction to KPFK)

### Critical Finding
The `Info.plist` currently has **WPFW** identifiers instead of KPFK. This suggests the project was cloned/copied from a WPFW template. We need to fix both the bundle ID AND the app display names.

---

## 📋 Files Requiring Changes

### 1. iOS Project Configuration (CRITICAL)
**File:** `ios/Runner.xcodeproj/project.pbxproj`
- **Lines to update:** 485, 502, 520, 536, 670, 693
- **Change:** `PRODUCT_BUNDLE_IDENTIFIER = app.pacifica.kpfk;` → `com.pacifica.kpfk;`
- **Also affects:** RunnerTests bundle ID (3 occurrences: `app.pacifica.kpfk.RunnerTests` → `com.pacifica.kpfk.RunnerTests`)

### 2. iOS Info.plist (CRITICAL)
**File:** `ios/Runner/Info.plist`
- **Line 12:** `CFBundleIdentifier` currently shows `com.pacifica.wpfw` → needs `com.pacifica.kpfk`
- **Line 8:** `CFBundleDisplayName` shows `WPFW` → needs `KPFK`
- **Line 16:** `CFBundleName` shows `WPFW` → needs `KPFK`
- **Line 41:** `BGTaskSchedulerPermittedIdentifiers` shows `com.pacifica.wpfw` → needs `com.pacifica.kpfk`

### 3. Android Configuration (NO CHANGE NEEDED)
**Files:** 
- `android/app/build.gradle` (line 33, 51)
- `android/app/src/main/AndroidManifest.xml` (line 6)
- `android/app/src/main/kotlin/app/pacifica/kpfk/*.kt` (package declarations)

**Decision:** Keep Android as `app.pacifica.kpfk` - Android and iOS can have different identifiers.

### 4. Flutter/Dart Code (NO CHANGE NEEDED)
**File:** `lib/services/samsung_media_session_service.dart` (line 17)
- **Current:** `MethodChannel('app.pacifica.kpfk/samsung_media_session')`
- **Decision:** This is a method channel name, not a bundle ID. Keep as-is for consistency with Android.

### 5. Documentation
**File:** `docs/APP_CONFIGURATION.md`
- Update example to reflect correct KPFK bundle ID

---

## ✅ Implementation Checklist

### Phase 1: iOS Bundle Identifier Updates
- [ ] Update `ios/Runner.xcodeproj/project.pbxproj` (6 occurrences for Runner, 3 for RunnerTests)
- [ ] Update `ios/Runner/Info.plist` CFBundleIdentifier
- [ ] Update `ios/Runner/Info.plist` BGTaskSchedulerPermittedIdentifiers

### Phase 2: App Branding Corrections (WPFW → KPFK)
- [ ] Update `ios/Runner/Info.plist` CFBundleDisplayName
- [ ] Update `ios/Runner/Info.plist` CFBundleName

### Phase 3: Clean Build Artifacts
- [ ] Delete `ios/build/` directory
- [ ] Delete `ios/Pods/` directory (will regenerate)
- [ ] Delete `ios/Podfile.lock`
- [ ] Run `flutter clean`

### Phase 4: Rebuild & Test
- [ ] Run `cd ios && pod install`
- [ ] Run `flutter pub get`
- [ ] Test build: `flutter build ios --release`
- [ ] Test run: `flutter run --release`

### Phase 5: Apple Developer Portal
- [ ] Create App ID for `com.pacifica.kpfk` at developer.apple.com
- [ ] Enable required capabilities (Background Modes - Audio)
- [ ] Create iOS App Development provisioning profile
- [ ] Download and install provisioning profile

---

## 🎯 Expected Changes Summary

| Location | Current Value | New Value | Reason |
|----------|--------------|-----------|--------|
| iOS project.pbxproj (Runner) | `app.pacifica.kpfk` | `com.pacifica.kpfk` | Apple Developer requirement |
| iOS project.pbxproj (RunnerTests) | `app.pacifica.kpfk.RunnerTests` | `com.pacifica.kpfk.RunnerTests` | Consistency with main bundle |
| Info.plist CFBundleIdentifier | `com.pacifica.wpfw` | `com.pacifica.kpfk` | Fix WPFW→KPFK branding |
| Info.plist CFBundleDisplayName | `WPFW` | `KPFK` | Correct app name |
| Info.plist CFBundleName | `WPFW` | `KPFK` | Correct app name |
| Info.plist BGTaskScheduler | `com.pacifica.wpfw` | `com.pacifica.kpfk` | Match bundle ID |
| Android (all) | `app.pacifica.kpfk` | **NO CHANGE** | Android can differ from iOS |

---

## ⚠️ Important Notes

1. **Platform Independence:** iOS and Android can have different bundle/package identifiers. We're only changing iOS.

2. **Method Channels:** The Dart method channel name `app.pacifica.kpfk/samsung_media_session` is Android-specific and should NOT be changed.

3. **Build Artifacts:** After making changes, a full clean build is required. Xcode caches can cause issues.

4. **Provisioning:** You MUST create the App ID in Apple Developer Portal before the build will succeed.

5. **WPFW Remnants:** This project was clearly templated from WPFW. We're fixing all WPFW references to KPFK.

6. **Testing:** After changes, test on a physical device to ensure provisioning works correctly.

---

## 🚀 Post-Implementation Verification

```bash
# Verify iOS bundle ID in project
grep -r "PRODUCT_BUNDLE_IDENTIFIER" ios/Runner.xcodeproj/project.pbxproj

# Verify Info.plist
grep -A 1 "CFBundleIdentifier" ios/Runner/Info.plist

# Clean and rebuild
flutter clean
cd ios && pod install && cd ..
flutter build ios --release
```

---

## 📝 Rollback Plan

If issues arise:
1. Revert changes to `ios/Runner.xcodeproj/project.pbxproj`
2. Revert changes to `ios/Runner/Info.plist`
3. Run `flutter clean && cd ios && pod install`
4. Return to original bundle ID `app.pacifica.kpfk`

However, since the original ID is unavailable in Apple Developer, rollback is not a viable solution. Forward progress only.
