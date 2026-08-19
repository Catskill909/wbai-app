# WBAI — Release Testing Handoff

**Written:** 2026-08-19 · **For:** the next WBAI build/test session (a few days out)
**Current version:** `1.0.1+8` · **Sister app:** KPFK, shipped `1.0.2+13`

WBAI received a batch of ported fixes it has **never been run with on any
device** — not iOS, not Android. This document is the complete list of what
changed, what must be tested, and what is still outstanding. Nothing here has
been verified on hardware.

---

## 1. Read this first — the one rule

**The play button ALWAYS plays the live stream and NEVER the cache.**

`play()` rebuilds the audio source unconditionally, every platform, every press.
There is no resume path, no staleness window, no platform gate.

The iOS lock-screen "previous app flashes on play" is a **cosmetic** bug whose
correct fix is the native `reassertNowPlaying` pre-claim in
`ios/Runner/AppDelegate.swift`. It must **never** be fixed by resuming a stale
buffer in `play()`. That trade caused a release blocker on KPFK — stale audio
followed by silence — and the same defect had been ported here.

`test/live_stream_always_rebuilds_test.dart` fails the build if this is
violated. Background: [audio-play-bug.md](audio-play-bug.md).

---

## 2. What changed in WBAI (all untested on device)

| Commit | Change |
|---|---|
| `f1cf916` | Debug outage panel (debug-only bug icon → `DebugOutagePage`); outage notice now emitted **before** slow player cleanup, so the modal is not delayed by up to a minute |
| `67563c3` | **The live-stream fix.** `play()` always rebuilds; `completed` triggers reconnect instead of a silent stop; `_handleError` documented as log-only; 6s M3U timeout. **Plus the native `reassertNowPlaying` pre-claim, which WBAI did not previously have** |
| `c79621c` | Android audit: reverted a notification-blanking regression; guarded `_reconnect()`'s rebuild so reconnects no longer blank the lock screen |
| `63b18fe` | `Info.plist`: removed BGTask key, **fixed a duplicate `UIBackgroundModes` key**, added `ITSAppUsesNonExemptEncryption`. Also removed the mic key — **which was wrong, and reverted below** |
| `9516934` | **Restored `NSMicrophoneUsageDescription`** after KPFK's build was rejected (ITMS-90683), and added `test/info_plist_required_keys_test.dart` to stop it recurring |

### ⚠️ `NSMicrophoneUsageDescription` must NEVER be removed

Earlier in the same session it was deleted from both apps on the reasoning that
neither has a microphone feature. KPFK's build `1.0.2+13` was then **rejected**:

> **ITMS-90683: Missing purpose string in Info.plist** … If you're using external
> libraries or SDKs, they may reference APIs that require a purpose string.
> **While your app might not use these APIs, a purpose string is still required.**

**Why it is mandatory:** Apple scans every linked binary, *including embedded
frameworks*. Two plugins here reference microphone APIs — `audio_session`
(AVAudioSession record APIs) and `flutter_inappwebview_ios` (WebView
`getUserMedia`). Checking the main `Runner` binary is **not** sufficient; that is
exactly the mistake that caused the rejection. Scan `Runner.app/Frameworks/`.

**It fails in both directions**, which is why it has flip-flopped repeatedly:
- **Removed** → ITMS-90683, upload rejected.
- **Present but dismissive** (`"This app does not use the microphone"`) → passes
  the scanner, but invites an App Review **5.1.1** question about why mic access
  is declared at all.

Correct state: **present, with a string that honestly explains it**. Guarded by
`test/info_plist_required_keys_test.dart`, which fails the build if the key is
missing, the string is dismissive/too short, `ITSAppUsesNonExemptEncryption` is
absent, or `UIBackgroundModes` is not declared exactly once.

WBAI never shipped the removal — it was caught and reverted on KPFK first.

---

### The two highest-risk items

**A. `reassertNowPlaying` is brand new here and has never run.**
On KPFK, deleting the resume path was safe *because* that native pre-claim
already existed and was proven. WBAI had no equivalent — it was written from
scratch on 2026-08-18 and modelled on KPFK's. If the lock-screen flash appears,
this is why, and the fix belongs in that Swift method.

**B. `UIBackgroundModes` was declared twice** in WBAI's `Info.plist` and is now
declared once. `plutil -lint` accepts duplicates, so this went unnoticed —
but only one survives parsing, and that key is what background audio depends on.
**Background playback must be explicitly retested.**

---

## 3. iOS test matrix — none of this has been run

Debug build, live logs (`flutter run -d <iphone>`, tail the output). Release
builds print nothing — the logger is `kDebugMode`-gated.

| # | Test | Pass criteria |
|---|---|---|
| 1 | Cold start → play | Live audio. Play→Ready ~1.5s |
| 2 | **Pause → 5+ min dormant → play** | **LIVE audio, and it KEEPS playing.** Any stale audio, or a stop after a few seconds, is a FAIL |
| 3 | Same as 2, but press play **on the lock screen** | Identical result |
| 4 | Quick pause → play (<10s) | Live, no stall |
| 5 | **Background playback, 5+ min, screen locked** | Uninterrupted. **This is the `UIBackgroundModes` regression check (§2B) — do not skip** |
| 6 | **Flash check:** play Spotify/Music briefly, then WBAI → pause → lock → play | **No flash** of the other app's art. This exercises the brand-new pre-claim (§2A) |
| 7 | Lock-screen metadata + artwork | Show name, host, art all populate and stay stable |
| 8 | Airplane mode mid-stream | Reconnect attempts, then the notice modal — not silence |

**Log markers.** Every play must show:
```
🎯 LIVE-ONLY: rebuilding AudioSource from the live edge (unconditional)
```
If you ever see `iOS RESUME-IN-PLACE: source alive`, the build did not take.

A dead stream should show, followed by recovery:
```
🎵 AUDIO STATE: Completed on a LIVE stream = stream died - reconnecting
```

---

## 4. Android test matrix — none of this has been run

**Use `adb logcat`, not flutter logs.**

| # | Test | Pass criteria |
|---|---|---|
| 1 | Pause → 5+ min dormant → play | Live audio, keeps playing (Android always rebuilt, so this should be unchanged) |
| 2 | **Play → drop network mid-stream → restore** | Reconnect happens and **notification art does NOT blank** — this is the `_reconnect()` guard from `c79621c` |
| 3 | **Network loss → recovery while paused** | Show info + lock screen **stay populated** — this is the reverted `resetToColdStart` regression |
| 4 | Swipe app from recents **while playing** | Notification clears, no orphan service |
| 5 | Swipe from recents **while paused** | Notification clears (historically the fragile case) |
| 6 | Sleep timer expiry | Audio stops, tray clears |
| 7 | Lock-screen play/pause/art through all of the above | Art stable, no blanking |

---

## 5. Outstanding — must be decided/done before release

### B1 — Version bump (BLOCKER when releasing)

Still `1.0.1+8`. Bump `pubspec.yaml`, then **regenerate the iOS build config**:

```
flutter build ios --config-only
```

Without that step Xcode Archive keeps stamping the old build number no matter
what `pubspec.yaml` says. Verify in the built binary, not the source:

```
plutil -extract CFBundleVersion raw -o - build/ios/iphoneos/Runner.app/Info.plist
```

> ⚠️ Always pass `-o -` to `plutil -extract`. **Without it, `plutil` overwrites
> the input file** with the extracted value. This destroyed WBAI's `Info.plist`
> during this session (recovered from git).

Android needs nothing — `versionCode` derives from the git commit count.

### B2 — Android 13+ never requests notification permission (BLOCKER)

Identical to KPFK, unfixed in **both** apps.

`POST_NOTIFICATIONS` is declared in the manifest but **never requested at
runtime** — not by the app, and not by `audio_service` 0.18.x. From Android 13
(API 33) that permission is denied by default, so the foreground service runs
but its notification is suppressed. That notification **is** the media control
surface, so affected users get audio with no controls and no explanation.

WBAI targets API 36, so this hits most of the Play audience.

**Test it on the `Android16_API36` emulator** (`flutter emulators`). The Samsung
SM-S737TL is Android 8.1 / API 27, where the permission is granted at install —
**the bug is structurally invisible on that device.**

Fix: request `POST_NOTIFICATIONS` at or before first playback on API 33+, with a
graceful path if denied.

---

## 6. Confirmed healthy — no action

- `flutter analyze` clean · **83/83 tests** · `plutil -lint` OK
- Debug surfaces hard-gated: `DebugStreamOverride.url` returns null outside
  `kDebugMode`, so a release binary always resolves to the live stream
- Release logging silent (`SEVERE` only, no console output)
- Android permissions minimal: INTERNET, WAKE_LOCK, FOREGROUND_SERVICE,
  FOREGROUND_SERVICE_MEDIA_PLAYBACK, POST_NOTIFICATIONS
- **No signing credentials in the repo.** No `.jks` / `key.properties` tracked;
  `build.gradle` reads from `keystoreProperties`; no hardcoded password. (KPFK
  had a plaintext password in a public repo — WBAI does **not**.)
- **No `NSAppTransportSecurity` block**, so WBAI is already on Apple's ATS
  defaults. The ATS scoping item in KPFK's audit does **not** apply here.

### Known, deliberately not fixed

- `lib/test_lockscreen.dart` — 297-line dead alternate entrypoint, referenced
  nowhere and not compiled into the release. Hygiene only.
- Dependencies behind latest (`just_audio` 0.9.x, `audio_session` 0.1.x).
  **Do not upgrade before this release** — that is the exact layer being
  verified. Early next cycle, with a full device retest.

---

## 7. Sister-app parity

KPFK is the lead app; fixes are made there and ported here. As of 2026-08-19
WBAI has **everything KPFK has**, except:

| Item | KPFK | WBAI |
|---|---|---|
| Live-stream fix + native pre-claim | ✅ device-verified | ✅ ported, **untested** |
| Android audit fixes | ✅ | ✅ ported, untested |
| `Info.plist` cleanup | ✅ | ✅ (plus duplicate-key fix) |
| Version bumped for release | ✅ `1.0.2+13` | ❌ still `1.0.1+8` |
| Android 13+ notification permission | ❌ outstanding | ❌ outstanding |

KPFK's equivalent documents: `docs/production-readiness-audit.md` and
`docs/audio-play-bug.md` in `/Users/paulhenshaw/Desktop/kpfk-app`.
