# WBAI Radio App — Handoff Document

**Cloned from**: `/Users/paulhenshaw/Desktop/kpfk-app/kpfk_radio/`
**App location**: `/Users/paulhenshaw/Desktop/wbai-app/wbai_radio/`
**Clone date**: 2026-04-01
**Status**: Clone complete — compiles clean, ready for asset swap & app store setup

---

## What Was Done

All KPFK identifiers have been replaced with WBAI equivalents. `dart analyze` returns **0 errors, 0 warnings**.

### Identifiers Swapped

| What | Old | New |
|------|-----|-----|
| Dart package | `kpfk_radio` | `wbai_radio` |
| Android app ID | `app.pacifica.kpfk` | `app.pacifica.wbai` |
| iOS bundle ID | `com.pacifica.kpfk` | `com.pacifica.wbai` |
| iOS test bundle ID | `com.pacifica.kpfk.RunnerTests` | `com.pacifica.wbai.RunnerTests` |
| Android notification channel | `com.kpfkfm.radio.audio` | `com.wbaifm.radio.audio` |
| Samsung session channel | `kpfk_samsung_media_channel` | `wbai_samsung_media_channel` |
| Method channel (Samsung) | `app.pacifica.kpfk/samsung_media_session` | `app.pacifica.wbai/samsung_media_session` |
| Method channel (metadata) | `com.kpfkfm.radio/metadata` | `com.wbaifm.radio/metadata` |
| Kotlin package dir | `kotlin/app/pacifica/kpfk/` | `kotlin/app/pacifica/wbai/` |
| Audio handler class | `KPFKAudioHandler` | `WBAIAudioHandler` |
| Audio handler file | `kpfk_audio_handler.dart` | `wbai_audio_handler.dart` |
| App class | `KPFKRadioApp` | `WBAIRadioApp` |
| Media item ID | `kpfk_live` | `wbai_live` |
| App display name | `KPFK` | `WBAI` |
| Version | `1.0.1+5` | `1.0.0+1` |

### Station Config (lib/core/constants/stream_constants.dart)

| Constant | Value |
|----------|-------|
| `streamUrl` | `https://streaming.wbai.org/wbai_verizon` ✓ confirmed |
| `stationName` | `WBAI` |
| `stationSlogan` | `Pacifica Radio` |
| `stationWebsite` | `https://www.wbai.org` |
| `scheduleUrl` | `https://www.wbai.org/schedule/` |
| `donateUrl` | `https://www.wbai.org/donate/` |
| `notificationChannelId` | `com.wbaifm.radio.audio` |

### Color Palette Applied (lib/presentation/theme/app_theme.dart)

Derived from the WBAI 4-quadrant logo. Class `WBAIColors` is defined in `app_theme.dart`.

| Role | Hex | Usage |
|------|-----|-------|
| Dark Brown | `#3B2828` | Scaffold background, splash screen |
| Blue | `#1BB4D8` | Accent, interactive, progress indicator |
| Mid Gray | `#6E7E8C` | Cards, surfaces |
| Light Gray | `#9BA5AF` | Dividers, secondary text |
| White | `#FFFFFF` | All primary text |

---

## Still Needed Before Launch

### Assets (placeholders from KPFK are in place — app runs but shows wrong branding)

- [ ] **App icon** — replace `assets/icons/app_icon.png` (1024×1024 PNG, no alpha)
- [ ] **Splash icon** — replace `assets/icons/splash_icon_fixed.png` (used for Android 12+ and iOS)
- [ ] **Header image** — replace `assets/images/header.png`
- [ ] Run `flutter pub run flutter_launcher_icons` after replacing app icon
- [ ] Run `flutter pub run flutter_native_splash:create` after replacing splash icon

### URLs to verify / update in stream_constants.dart

- [ ] `stationLogo` — needs real WBAI logo CDN URL
- [ ] `showArchiveUrl` — confirm correct WBAI archive URL
- [ ] `facebookUrl` — confirm handle
- [ ] `twitterUrl` — confirm handle
- [ ] `instagramUrl` — confirm handle
- [ ] `youtubeUrl` — confirm handle
- [ ] `emailAddress` — confirm GM email
- [ ] `metadataUrl` — WBAI now-playing/metadata API (currently set to localhost dev proxy)

### WBAI broadcast frequency
- Currently set to `WBAI 99.5 FM` in `wbai_audio_handler.dart` and `SamsungMediaSessionManager.kt` — confirm correct frequency

### App Store / Play Store
- [ ] Create app entry on App Store Connect for bundle ID `com.pacifica.wbai`
- [ ] Create app entry on Google Play Console for app ID `app.pacifica.wbai`
- [ ] Generate and configure Android signing keystore for release builds

### Git
The project still has the KPFK git history. To start fresh:
```bash
cd /Users/paulhenshaw/Desktop/wbai-app/wbai_radio
rm -rf .git
git init
git add .
git commit -m "Initial WBAI Radio app"
```

---

## First Build Commands

```bash
cd /Users/paulhenshaw/Desktop/wbai-app/wbai_radio

# Dependencies
flutter pub get

# iOS (first time)
cd ios && pod install && cd ..

# Debug builds to verify
flutter build ios --debug
flutter build apk --debug
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `lib/core/constants/stream_constants.dart` | All station URLs, stream URL, social links |
| `lib/presentation/theme/app_theme.dart` | WBAI color palette (`WBAIColors`) + theme |
| `lib/services/audio_service/wbai_audio_handler.dart` | Audio playback, media session, notifications |
| `android/app/src/main/kotlin/app/pacifica/wbai/MainActivity.kt` | Android native + Samsung media session bridge |
| `ios/Runner/Info.plist` | iOS app name, bundle ID, background audio |
