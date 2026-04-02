# KPFK Radio Streaming App

A Flutter-based radio streaming application for KPFK 90.7 FM with advanced features including background audio playback, lockscreen controls, sleep timer, and accessibility support.

## Current Version: v1.0.0+2

### Recent Updates
- Added custom typography using Google Fonts (Oswald & Poppins)
- Implemented automated version management using cider
- Enhanced UI consistency with new font styles

### Latest Updates (Sep 12, 2025)
- ✅ **CRITICAL BUG RESOLVED**: iOS lockscreen audio controls fully functional
  - Fixed lockscreen play/pause buttons that were previously non-responsive
  - Resolved stuck loading states when using lockscreen controls
  - Implemented proper audio command routing through StreamRepository singleton
  - Perfect synchronization between lockscreen, app controls, and system audio interfaces
- Ready for distribution with complete audio functionality

### Previous Updates (Sep 5, 2025)
- Basic accessibility support implemented (non-visual changes only):
  - Play/Pause control labeled and operable with screen readers (TalkBack/VoiceOver).
  - Live announcements for playback transitions (Loading, Buffering, Playing, Paused) and error states.
  - Loading spinner marked as a live region so "Loading audio" is read without moving focus.
  - Donate sheet: labeled close button, announce page loaded, and announce before opening external browser.
- For details and next steps, see project documentation

## Features

- Streaming audio playback with background support
  - Powered by `just_audio`, `audio_service`, and `audio_session`.
  - ✅ iOS lockscreen controls and metadata integration fully operational.
  - ✅ Critical lockscreen bug resolved - all audio controls synchronized across app and system interfaces.
  - 📖 **Complete system documentation**: [../AUDIO_METADATA_MASTER_REFERENCE.md](../AUDIO_METADATA_MASTER_REFERENCE.md)

- Advanced Sleep Timer (overlay)
  - Full-screen dark-themed overlay with presets (15/30/45/60m) and a minute slider.
  - Countdown, pause/resume, and cancel.
  - On completion: performs a cold-start audio reset (stop, dispose player, clear iOS lockscreen, return to idle) to avoid residual state.
  - Entry: Bottom-right Alarm button on `HomePage`.
  - Docs: [timer.md](../timer.md)
  - Source: `lib/presentation/widgets/sleep_timer_overlay.dart`, `lib/presentation/bloc/sleep_timer_cubit.dart`

- Donate Modal WebView
  - In-app modal sheet with `flutter_inappwebview`.
  - Handles external links by opening the system browser.
  - Accessible close control and announcements for page load/external launches.
  - Source: `lib/presentation/widgets/donate_webview_sheet.dart`

- Pacifica Apps & Services
  - Grid of Pacifica posts/apps/services fetched from WordPress API.
  - Replaces Settings when tapping the top-right icon on `HomePage`.
  - Source: `lib/presentation/pages/pacifica_apps_page.dart`, `lib/presentation/bloc/pacifica_bloc.dart`, `lib/data/repositories/pacifica_repository.dart`

- Offline awareness & recovery
  - Connectivity monitoring with graceful offline overlays and retry controls.
  - Source: `lib/presentation/widgets/offline_modal.dart`, `lib/presentation/widgets/offline_overlay.dart`, `presentation/bloc/connectivity_cubit.dart`

- Audio Server Error Handling (December 2024)
  - Robust server error detection and user feedback system.
  - Pre-flight server health checks before playback attempts.
  - AudioServerErrorModal for user-friendly server error messaging.
  - Complete audio controls reset (play button, lockscreen, notifications) on server errors.
  - Comprehensive testing strategy with AudioServerTestingStrategy for simulating server failures.
  - Source: `lib/presentation/widgets/audio_server_error_modal.dart`, `lib/core/services/audio_server_health_checker.dart`, `lib/core/testing/audio_server_testing_strategy.dart`

- Accessibility baseline (Sep 5, 2025)
  - Screen-reader labels for core playback and donate flows, live announcements for playback states and errors.
  - Plan and next steps documented in [accessibity.md](../accessibity.md).

### Resolved: iOS Lockscreen Metadata
- Resolved: Stable lockscreen metadata and working remote controls on iOS.
- Fix summary: Implemented native `MPNowPlayingInfoCenter` updates via platform channel, debounced updates to avoid churn, and wired `MPRemoteCommandCenter` handlers to Flutter (play/pause/toggle) so taps control the `KPFKAudioHandler`.
- Verification: VoiceOver reads current show/song on lockscreen; controls operate playback reliably without flicker.

---

## Architecture Overview

- **Framework**: Flutter (Dart)
- **State management**: `flutter_bloc` + `get_it` service locator
- **Audio playback**: `just_audio` with `audio_service` and `audio_session`
- **Networking**: `dio` and `http`
- **Storage/Device**: `shared_preferences`, `path_provider`, `device_info_plus`
- **Web content**: `flutter_inappwebview`
- **UI**: Material 3 theme, Google Fonts, SVG, cached images

High-level flow:
- `HomePage` (`lib/presentation/pages/home_page.dart`) renders the main experience: station artwork, metadata, and a single large play/pause control that dispatches events to `StreamBloc`.
- `StreamBloc` (`lib/presentation/bloc/stream_bloc.dart`) orchestrates playback via `StreamRepository` (`lib/data/repositories/stream_repository.dart`).
- `KPFKAudioHandler` (`lib/services/audio_service/kpfk_audio_handler.dart`) wraps `just_audio` and integrates with `audio_service` for background/notification control.
- Metadata services (`lib/services/metadata_service*.dart`) fetch and adapt current/next show info and song data to the UI and iOS lockscreen.
- Platform integration for iOS lockscreen uses native `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` via platform channels.

## Project Structure

- `lib/presentation/pages/`
  - `home_page.dart`, `pacifica_apps_page.dart`
- `lib/presentation/widgets/`
  - `sleep_timer_overlay.dart`, `donate_webview_sheet.dart`, `app_drawer.dart`, `offline_modal.dart`, `offline_overlay.dart`, `sliding_panel.dart`, `station_webview.dart`
- `lib/presentation/bloc/`
  - `stream_bloc.dart`, `sleep_timer_cubit.dart`, `connectivity_cubit.dart`, `pacifica_bloc.dart`
- `lib/services/`
  - `audio_service/kpfk_audio_handler.dart`
  - `metadata_service.dart`, `metadata_service_native.dart`, `metadata/lockscreen_service.dart`, `ios_lockscreen_service.dart`
- `lib/data/`
  - `repositories/` (stream, pacifica, affiliate)
  - `models/` and `domain/models/`
- `lib/core/`
  - `di/` service locator, `services/` (connectivity, audio state manager, logger), `constants/`, `utils/`
- Docs: `docs/` (architecture notes, platform specifics, timelines)

## Packages / Dependencies

From `pubspec.yaml`:
- Audio: `just_audio`, `audio_service`, `audio_session`, `radio_player` (experimental)
- WebView: `flutter_inappwebview`
- State: `flutter_bloc`, `get_it`
- Network/Storage: `dio`, `http`, `connectivity_plus`, `path_provider`, `shared_preferences`, `device_info_plus`, `url_launcher`
- UI: `flutter_svg`, `cached_network_image`, `google_fonts`, `cupertino_icons`, `equatable`, `flutter_native_splash`
- Dev: `flutter_test`, `flutter_lints`, `flutter_launcher_icons`

See: `pubspec.yaml` for version pins.

## Setup & Build

Prereqs:
- Flutter SDK (stable) and platform toolchains (Xcode for iOS, Android SDK/NDK for Android)

Install dependencies:
```bash
flutter pub get
```

Run (Android):
```bash
flutter run -d android
```

Run (iOS Simulator):
```bash
flutter run -d ios
```

Build:
```bash
flutter build apk   # Android
flutter build ios   # iOS (requires Xcode signing)
```

## Usage

- Open the app to the main `HomePage`.
- Tap the large play/pause button to start/stop the KPFK stream.
- Bottom-right Alarm button opens the Sleep Timer overlay.
- Bottom-left Donate button opens the in-app Donate modal WebView; external links open in the system browser.
- Tap the top-right icon to open the Pacifica Apps & Services grid.

## Accessibility

Basic screen reader support (Sep 5, 2025):
- Dynamic labels/hints for the play/pause control.
- Announcements for playback transitions (Loading, Buffering, Playing, Paused) and errors.
- Donate modal: labeled close button; announcements for page load and external browser opening.

Planned next steps (non-visual): focus traps in modals, `MergeSemantics` for metadata blocks, contrast/tap-target audits, and dev-only a11y tooling.

## Platform specifics: iOS lockscreen metadata

- Status: ✅ Fully functional
- Implementation: Native `MPNowPlayingInfoCenter` updates and `MPRemoteCommandCenter` handlers via platform channels from Flutter to Swift.
- Features: Stable metadata display, responsive controls, proper synchronization with app state

## Troubleshooting

- Stream fails to start or frequently buffers
  - Check connectivity; see `connectivity_plus` status and retry from Snackbar.
  - Review logs via `LoggerService` in `lib/core/services/logger_service.dart`.

- iOS lockscreen shows stale or no metadata
  - Confirm native integration is on the correct branch and platform channels are wired.
  - Refer to the iOS lockscreen docs (above) for current status and test steps.

- WebView links not opening externally
  - Ensure `url_launcher` is properly configured for iOS/Android.
  - In Donate modal, unsupported schemes are handed off to the system browser.

## Roadmap / Backlog

- Add focus management and semantics grouping for overlays/modals.
- Introduce CI a11y checks (e.g., `accessibility_lint`) and basic widget tests for semantics.
- Improve contrast and typography in dark theme as needed (AA level).
- Explore additional playback optimizations and features.

## Station Information

- **Station**: KPFK 90.7 FM
- **Network**: Pacifica Radio
- **Website**: https://www.kpfk.org
- **Stream URL**: https://docs.pacifica.org/kpfk/kpfk.m3u
- **Email**: gm@kpfk.org

### Social Media
- **Facebook**: https://www.facebook.com/KPFK90.7/
- **Twitter/X**: https://x.com/KPFK/
- **Instagram**: https://www.instagram.com/kpfk/
- **YouTube**: https://www.youtube.com/@KPFKTV/videos/

## Configuration Files

Key configuration files:
- `lib/core/constants/stream_constants.dart` - Stream URLs, station info, social media links
- `pubspec.yaml` - Dependencies and app metadata
- `android/app/build.gradle` - Android build configuration
- `ios/Runner.xcodeproj/project.pbxproj` - iOS build configuration
