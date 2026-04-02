# iOS Build Warnings — Deep Audit & Fix Plan

> Generated: 2025-03-12 | **Last updated: 2025-03-12 1:10 PM**
> Project: KPFK Radio iOS (Flutter)
> Xcode deployment target: **iOS 13.0** (project & Podfile aligned)

---

## Progress Tracker

| Phase | Description | Status |
|-------|-------------|--------|
| **Phase 1** | Easy wins — our code | ✅ **DONE** (committed `028de24`) |
| **Phase 2** | Deployment target alignment | ✅ **DONE** (committed `d9be03d`) |
| **Phase 3A** | Suppress linker warning + Pods recommended settings | ✅ **DONE** (linker flag in Podfile + project.pbxproj; Pods settings = Xcode manual step) |
| **Phase 3B** | Upgrade `url_launcher` and `flutter_native_splash` | ✅ **DONE** (`flutter_native_splash` upgraded to 2.4.7; `url_launcher_ios` 6.4.x needs newer Flutter SDK — unfixable) |
| **Phase 3C** | Upgrade `flutter_inappwebview` | 🔲 Pending (risky — beta) |
| **Unfixable** | `audio_service` deprecated API | ❌ Awaiting upstream author |

---

## Current Remaining Warnings (post Phase 1 & 2)

| # | Warning | Source | Fixable? | Phase |
|---|---------|--------|----------|-------|
| 1 | Duplicate library `-lswiftCoreGraphics` | Xcode 15+ linker behavior | ✅ Suppress via linker flag | 3A |
| 2 | Pods — "Update to recommended settings" | Pods.xcodeproj | ✅ Let Xcode update | 3A |
| 3 | `audio_service` — `initWithImage:` deprecated | Third-party (v0.18.18) | ❌ **No fix available** — known since 2021, author hasn't patched | Unfixable |
| 4 | `flutter_inappwebview_ios` — 20+ deprecation warnings | Third-party (v1.2.0-beta.2) | ⚠️ beta.3 exists but **does NOT fix** these warnings | 3C |
| 5 | `flutter_native_splash` — xcprivacy build rule | Third-party (v2.4.4) | ✅ **v2.4.7 available** — podspec fix included | 3B |
| 6 | `url_launcher_ios` — `keyWindow` deprecated | Third-party (v6.3.3) | ❌ **v6.4.x fixes this BUT requires Flutter 3.38+/Dart 3.10+** — our SDK is 3.6.2 | Unfixable (SDK) |

---

## COMPLETED — Phase 1: Easy Wins

All done and committed in `028de24`:
- ✅ `.allowBluetooth` → `.allowBluetoothA2DP` (AppDelegate.swift + MetadataController.swift)
- ✅ Deleted 6 orphaned AppIcon PNGs (pre-iOS 7 legacy sizes)
- ✅ Removed ~130 lines of dead code in MetadataController.swift
- ✅ Added OTHER_LDFLAGS dedup in Podfile

---

## COMPLETED — Phase 2: Deployment Target Alignment

All done and committed in `d9be03d`:
- ✅ Podfile: `IPHONEOS_DEPLOYMENT_TARGET` changed from `12.0` → `13.0`
- ✅ Full clean rebuild: `flutter clean` + `pod deintegrate` + `pod install`
- ✅ Eliminated all 8 "Building for iOS-12.0 but linking with 13.0" warnings
- ✅ Fixed archive build failure (`Flutter/Flutter.h file not found`)

---

## Phase 3A — Suppress Linker Warning + Pods Settings (~5 min)

### 3A.1 Duplicate library `-lswiftCoreGraphics`

**Warning:** `Ignoring duplicate libraries: '-lswiftCoreGraphics'`

**Research findings (source: [Indie Stack blog](https://indiestack.com/2023/10/xcode-15-duplicate-library-linker-warnings/)):**
- This is a **known Xcode 15+ bug** (Apple FB13229994)
- Xcode's linker now warns on duplicate library flags, but Xcode *itself* generates the duplicates via derived dependency resolution
- The `OTHER_LDFLAGS.uniq` approach in Podfile doesn't help because the duplicate comes from Xcode's implicit Swift library linking, NOT from explicit flags
- **The correct fix** is to pass `-Wl,-no_warn_duplicate_libraries` to the linker

**Fix — add to Podfile `post_install`:**
```ruby
# Suppress Xcode 15+ duplicate library linker warning (Apple bug FB13229994)
installer.pods_project.build_configurations.each do |config|
  config.build_settings['OTHER_LDFLAGS'] ||= ['$(inherited)']
  config.build_settings['OTHER_LDFLAGS'] << '-Wl,-no_warn_duplicate_libraries'
end
```

Also add to Runner target in Xcode:
- Build Settings → Other Linker Flags → add `-Wl,-no_warn_duplicate_libraries`

**Risk:** None. This only suppresses the cosmetic warning. The duplicate is already being ignored by the linker.

### 3A.2 Pods — "Update to recommended settings"

**Warning:** Yellow triangle on `Pods.xcodeproj` — "Update to recommended settings"

**Fix:** In Xcode, click the warning on the Pods project and "Perform Changes". Same settings update we did for Runner (remove deprecated embed Swift flags).

**Risk:** None. These are Xcode modernization settings.

---

## Phase 3B — Safe Package Upgrades (~15 min + testing)

### 3B.1 `url_launcher_ios` — `keyWindow` deprecated

**Current:** `url_launcher: ^6.2.5` → resolves to `url_launcher_ios: 6.3.3`
**Warning:** `'keyWindow' was deprecated in iOS 13.0: Should not be used for applications that support multiple scenes`

**Research findings:**
- `url_launcher_ios` **6.4.0** added UIScene compatibility and fixed `keyWindow` deprecation
- `url_launcher_ios` **6.4.1** is the latest (requires Flutter 3.38+)
- Our Dart SDK is `^3.6.2` which supports these versions
- The parent package `url_launcher` **6.3.1** is already installed

**Fix — `pubspec.yaml`:**
```yaml
# Before:
url_launcher: ^6.2.5
# After:
url_launcher: ^6.3.1
```
Then `flutter pub upgrade url_launcher` — this should pull `url_launcher_ios` ≥6.4.0.

**Risk:** Low. This is a first-party Flutter team package with stable releases.

### 3B.2 `flutter_native_splash` — xcprivacy build rule

**Current:** `flutter_native_splash: ^2.3.10` → resolves to v2.4.4
**Warning:** `no rule to process file 'PrivacyInfo.xcprivacy' of type 'text.xml'`

**Research findings (source: [GitHub issue #761](https://github.com/jonbhanson/flutter_native_splash/issues/761)):**
- The podspec incorrectly includes `PrivacyInfo.xcprivacy` in `source_files` instead of `resource_bundles`
- **v2.4.7 is available** and likely includes the podspec fix
- This is a build-time-only warning — the privacy manifest still works correctly

**Fix — `pubspec.yaml`:**
```yaml
# Before:
flutter_native_splash: ^2.3.10
# After:
flutter_native_splash: ^2.4.7
```
Then `flutter pub upgrade flutter_native_splash`.

**Risk:** Low. Splash screen generation is done at build time. Test that splash still displays correctly.

---

## Phase 3C — Risky Package Upgrade (flutter_inappwebview)

### 3C.1 `flutter_inappwebview_ios` — 20+ deprecation warnings

**Current:** `flutter_inappwebview: ^6.1.8` → resolves to `flutter_inappwebview_ios: 1.2.0-beta.2`
**Warnings (20+):** `keyWindow`, `spotlightSuggestion`, `clearCache`, `selectionGranularity`, `SFAuthenticationSession`, `SecTrustEvaluate`, storyboard target mismatch, etc.

**Research findings:**
- `flutter_inappwebview: 6.2.0-beta.3` was released **11 days ago**
- The beta.3 changelog fixes a few bugs but **does NOT address the iOS deprecation warnings**
- The stable version is `6.1.5` but it uses the same `flutter_inappwebview_ios: 1.2.0-beta.2`
- **These deprecation warnings are baked into the plugin source code** — the author has not updated them
- All deprecated APIs still function correctly on current iOS versions

**Recommendation:** **Do NOT upgrade yet.** The warnings are cosmetic only. Wait for a stable release that addresses deprecations. Upgrading beta→beta risks introducing new bugs with no warning reduction.

**Alternative:** If the warnings are truly bothersome, they can be suppressed per-pod in the Podfile:
```ruby
# Suppress deprecation warnings for flutter_inappwebview_ios
if target.name == 'flutter_inappwebview_ios'
  config.build_settings['GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS'] = 'NO'
end
```
This hides the warnings but does not fix the underlying code.

---

## Unfixable — `audio_service` (v0.18.18)

**Warning:** `'initWithImage:' is deprecated: first deprecated in iOS 10.0`

**Research findings:**
- This warning has existed since **at least 2021** (Stack Overflow reports from Flutter 2.5.0 era)
- The fix is a one-line change in `AudioServicePlugin.m:213` — replace `initWithImage:` with `initWithBoundsSize:requestHandler:`
- The package author **has not released a fix** in any version up to 0.18.18
- `audio_service: 0.18.18` is the **latest version** on pub.dev
- No newer version exists to upgrade to

**Impact:** Zero functional impact. The deprecated API works on all iOS versions including iOS 18+. Apple has not removed it.

**Options:**
1. **Wait** for the author to release a fix (most practical)
2. **Fork** the package and patch the one line (overkill for a cosmetic warning)
3. **Suppress** with Podfile per-target `GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS = NO` (hides it)

---

## Recommended Next Steps

### Phase 3A — Do now (~5 min)
1. Add `-Wl,-no_warn_duplicate_libraries` linker flag (Podfile + Runner target)
2. Let Xcode update Pods recommended settings
3. Commit & push

### Phase 3B — DONE
- ✅ `flutter_native_splash` upgraded `^2.3.10` → `^2.4.7` (fixes xcprivacy warning)
- ❌ `url_launcher_ios` 6.4.x requires Flutter 3.38+/Dart 3.10+ — cannot upgrade with current SDK `^3.6.2`
- The `keyWindow` deprecation warning will persist until Flutter SDK is upgraded

### Phase 3C — Skip for now
- `flutter_inappwebview` — beta.3 does NOT fix the warnings. Wait for stable.

### Unfixable — Accept
- `audio_service` — No newer version available. Warning is cosmetic only.

---

## Phase 4 — Flutter SDK Upgrade (3.35.5 → 3.41.2)

**Current:** Flutter 3.35.5 / Dart 3.9.2 (Sep 2025)
**Latest stable:** Flutter 3.41.2 / Dart 3.10+ (Feb 2026)

### Why upgrade?
- `url_launcher_ios` 6.4.x (fixes `keyWindow` deprecation) requires Flutter 3.38+/Dart 3.10+
- Flutter 3.38 adopted **UISceneDelegate** — the same iOS architecture change that replaces `keyWindow`
- 6 months of bug fixes, performance improvements, and security patches

### Breaking changes to review (3.35 → 3.41)

**Flutter 3.38 (must pass through):**
- **UISceneDelegate adoption** — directly relevant to our iOS warnings; Flutter's own iOS embedding moves to scenes
- FontWeight now controls variable font weight attribute
- Material 3 tokens update — may affect theming/colors slightly
- SnackBar with action no longer auto-dismisses
- Default Android page transition changed to PredictiveBackPageTransitionBuilder
- Deprecations: `containsSemantics`, `findChildIndexCallback`, `OverlayPortal.targetsRootOverlay`

**Flutter 3.41 (latest stable):**
- **Android Gradle Plugin 9.0.0 migration required** — biggest risk item
- ListTile throws exception when wrapped in a colored widget (could affect our UI)
- Page transition builders reorganized
- Deprecations: `onReorder`, `cacheExtent`, `TextInputConnection.setStyle`

### Risk assessment

| Risk | Level | Notes |
|------|-------|-------|
| AGP 9.0.0 migration | ⚠️ Medium | Android build config changes needed |
| UISceneDelegate | Low | Flutter handles this internally |
| Material 3 tokens | Low | Minor color/theme adjustments if any |
| `flutter_inappwebview` beta | ⚠️ Medium | Beta plugin may not support new Flutter APIs |
| ListTile color change | Low | Check if we wrap ListTiles in colored widgets |
| Page transitions | Low | Default change only affects Android |

### Recommendation
- **Do it on a branch** — `flutter-upgrade`
- Upgrade incrementally: 3.35 → 3.38 first, build + test, then → 3.41
- Or just go straight to 3.41 (Flutter handles migrations)
- Run `dart fix --apply` after upgrade to auto-migrate deprecated APIs
- Biggest risk: `flutter_inappwebview` beta + AGP 9.0 migration
- Expected payoff: fixes `url_launcher_ios` keyWindow warning, possibly others
