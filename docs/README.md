# WBAI Radio — Documentation Index

This folder has grown organically (60+ files, many of them successive attempts
at the same lock-screen problem). Start here rather than guessing from filenames.

## ▶ Start here for the next build/test session

| Doc | What it's for |
| --- | --- |
| [RELEASE-TESTING-HANDOFF.md](RELEASE-TESTING-HANDOFF.md) | **Everything WBAI needs before release** — what changed, the full iOS + Android test matrices (none of it run yet), and the two outstanding blockers (version bump, Android 13+ notification permission) |

## Read before touching audio

| Doc | Guards against |
| --- | --- |
| [audio-play-bug.md](audio-play-bug.md) | **Live stream must ALWAYS play live, NEVER the cache.** `play()` rebuilds unconditionally — no resume path, no staleness window, no platform gate. Also: `completed` on a live stream is always a failure, never a clean stop. Includes the Android notification/MediaSession audit and the device-test matrix |

**The one rule that keeps getting traded away:** the iOS lock-screen "previous
app flashes on play" is a *cosmetic* bug whose correct fix is the native
`reassertNowPlaying` pre-claim in `ios/Runner/AppDelegate.swift`. It must **never**
be fixed by resuming a stale buffer in `play()`. That trade caused a release
blocker on KPFK (stale audio, then silence) and the same defect was ported here.
`test/live_stream_always_rebuilds_test.dart` fails the build if it comes back.

## Current feature/behaviour docs

| Doc | What it covers |
| --- | --- |
| [FEATURE_stream_offline_notice.md](FEATURE_stream_offline_notice.md) | The single acknowledged stream-notice modal (outage vs connection) |
| [STREAM_OFFLINE_MODAL_AUDIT.md](STREAM_OFFLINE_MODAL_AUDIT.md) | Audit behind that modal, plus the debug outage panel |
| [TESTING_outage_scenarios.md](TESTING_outage_scenarios.md) | How to rehearse failures without taking the station off air |
| [APP_CONFIGURATION.md](APP_CONFIGURATION.md) | App configuration reference |
| [AI_ASSISTED_DEV_GUIDELINES.md](AI_ASSISTED_DEV_GUIDELINES.md) | Working agreements for AI-assisted changes |

## Lock-screen archive

The many `LOCKSCREEN_*` files are a historical record of successive attempts,
kept for context. They are **not** current guidance — several recommend
approaches that were later reversed. For anything touching lock-screen behaviour,
treat `audio-play-bug.md` as authoritative and these as background.

## Sister app

WBAI shares a template with KPFK (`/Users/paulhenshaw/Desktop/kpfk-app`). Fixes
are normally made in one and ported to the other — check the other repo's
`docs/` before starting, and port back when done.
