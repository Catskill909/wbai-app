# WBAI Radio Streaming App

A Flutter-based radio streaming application for WBAI 99.5 FM — Pacifica Radio NYC — with background audio playback, lockscreen controls, sleep timer, and accessibility support.

## Current Version: v1.0.0+2

---

## Features

- **Live Stream Playback** — Background audio via `just_audio`, `audio_service`, and `audio_session`
  - iOS lockscreen controls and metadata integration
  - Android notification controls and Samsung MediaSession support
  - Stream URL: `https://streaming.wbai.org/wbai_verizon`

- **Sleep Timer** — Overlay with 15/30/60 min presets and minute slider
  - Countdown display, pause/resume, cancel
  - On completion: cold-start audio reset to idle
  - Source: `lib/presentation/widgets/sleep_timer_overlay.dart`, `lib/presentation/bloc/sleep_timer_cubit.dart`

- **Donate Modal WebView** — In-app sheet opening `https://docs.pacifica.org/wbai/donate/`
  - External links open in system browser
  - Source: `lib/presentation/widgets/donate_webview_sheet.dart`

- **Pacifica Apps & Services** — Grid of Pacifica posts fetched from WordPress API
  - Opens via top-right radio icon on `HomePage`
  - Source: `lib/presentation/pages/pacifica_apps_page.dart`

- **Side Drawer Navigation**
  - Program Schedule, Playlist Archive, Show Archive, Donate, WBAI Website, About Pacifica, Privacy Policy
  - Social icons: Facebook, Instagram, Twitter/X, Email
  - Source: `lib/presentation/widgets/app_drawer.dart`

- **Offline Awareness** — Connectivity monitoring with overlay and retry controls

- **Audio Server Health Checks** — Pre-flight checks before playback with user-friendly error modals

---

## Architecture Overview

- **Framework**: Flutter (Dart)
- **State management**: `flutter_bloc` + `get_it` service locator
- **Audio**: `just_audio` + `audio_service` + `audio_session`
- **Networking**: `dio`, `http`
- **WebView**: `flutter_inappwebview`
- **UI**: Material 3, Google Fonts (Oswald + Poppins), light/white theme

High-level flow:
- `HomePage` renders station artwork, metadata, and play/pause control → dispatches to `StreamBloc`
- `StreamBloc` orchestrates playback via `StreamRepository`
- `WBAIAudioHandler` wraps `just_audio` and integrates with `audio_service`
- `MetadataService` fetches current/next show info from the Pacifica confessor feed
- iOS lockscreen uses native `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` via platform channels

---

## Metadata & Images

- **Feed URL**: `https://confessor.kpfk.org/playlist/_pl_current_ary.php` *(shared Pacifica feed — temporary until WBAI feed is live)*
- **Show images**: `https://confessor.kpfk.org/pix/<filename>` (from `big_pix` field)
- **Metadata text**: show name, time, host, next show — fully functional

---

## Project Structure

- `lib/presentation/pages/` — `home_page.dart`, `pacifica_apps_page.dart`
- `lib/presentation/widgets/` — `app_drawer.dart`, `sleep_timer_overlay.dart`, `donate_webview_sheet.dart`, `audio_server_error_modal.dart`
- `lib/presentation/bloc/` — `stream_bloc.dart`, `sleep_timer_cubit.dart`, `connectivity_cubit.dart`
- `lib/services/audio_service/` — `wbai_audio_handler.dart`
- `lib/services/` — `metadata_service.dart`, `ios_lockscreen_service.dart`
- `lib/data/repositories/` — `stream_repository.dart`
- `lib/domain/models/` — `stream_metadata.dart` (UI layer)
- `lib/data/models/` — `stream_metadata.dart` (audio handler layer)
- `lib/core/constants/` — `stream_constants.dart` (all URLs and config)

---

## Setup & Build

```bash
flutter pub get
flutter run -d android
flutter run -d ios
flutter build apk    # Android
flutter build ios    # iOS (requires Xcode signing)
```

---

## Key Configuration

- `lib/core/constants/stream_constants.dart` — Stream URL, all menu/social URLs, station info
- `pubspec.yaml` — Dependencies and app metadata
- `android/app/build.gradle` — Android build config
- `ios/Runner.xcodeproj/project.pbxproj` — iOS build config

---

## Station Information

- **Station**: WBAI 99.5 FM
- **Network**: Pacifica Radio
- **Website**: https://www.wbai.org
- **Stream URL**: https://streaming.wbai.org/wbai_verizon
- **Email**: gm@wbai.org

### Social Media
- **Facebook**: https://www.facebook.com/WBAIradio/
- **Twitter/X**: https://x.com/wbai/
- **Instagram**: https://www.instagram.com/wbainyc/

---

## Troubleshooting

- **Stream fails to start** — Check connectivity; review `LoggerService` logs
- **iOS lockscreen stale metadata** — Confirm platform channels are wired; check `ios_lockscreen_service.dart`
- **WebView links not opening** — Ensure `url_launcher` is configured for iOS/Android
- **No show image** — Feed images served from `confessor.kpfk.org/pix/`; will update when WBAI feed is live
