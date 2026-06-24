# WBAI Android Fixes — June 2026

Reference for the Android fixes made to WBAI on 2026-06-24. Most were developed and
device-verified on the more-polished **KPFK** app first, then ported here (sister-app
workflow — KPFK and WBAI share a template). KPFK's parallel docs:
`kpfk-app/docs/android-build.md` and `kpfk-app/docs/lock-screen-bug.md`.

Device used for verification: Samsung Galaxy J7 (SM-S737TL, Android 8.1.0, API 27).

---

## 1. Startup speed — deferred stream pre-load (WBAI-specific)

**Symptom:** On launch the home screen sat on "Loading stream information…" placeholders
(text + image) for up to ~10s before showing the current show.

**Cause (found via `adb logcat`, not `flutter run` logs):** `WBAIAudioHandler._init()`
eagerly did `await _resolveStreamUrl()` + `await _player.setAudioSource()` to
pre-connect the live stream at app launch. Connecting the stream held up startup
(`Choreographer: Skipped 300+ frames`), so the UI stayed on the placeholder even though
metadata was already available.

**Fix:** Removed the eager source load from `_init()`. The stream source is now built
on demand in `play()` (which already had a cold/Android rebuild path). There is no
reason to buffer the live stream before the user presses play.

**File:** `lib/services/audio_service/wbai_audio_handler.dart` (`_init`).

**Note:** KPFK has the same eager `_init` load but is tolerated there (and it happens to
mask the placeholder by delaying first frame). KPFK was intentionally left unchanged.

---

## 2. Metadata fetch reliability — timeout + initial retry (the "30-second load")

**Symptom:** After the startup fix, the load time was inconsistent — sometimes ~2s,
sometimes up to ~30s, on "Loading stream information…".

**Cause (measured on device):** the metadata API responds in ~6–8s on a cold start, but
the dio timeout was **5s**. So the first fetch FAILED, and the only retry was the **30s
periodic timer** — a missed first fetch meant a ~30s wait.

**Fix:** in `metadata_service.dart`:
- Raised `_timeout` from 5s → **12s** so a slow-but-working response succeeds.
- Replaced the single constructor `_fetchMetadata()` with `_initialFetchWithRetry()` —
  retries the FIRST fetch every 2s (up to 6 attempts) instead of waiting 30s.

After the fix the first metadata arrives reliably at ~7s (the real API latency), never
30s. The remaining ~7s is the metadata server itself (`confessor.kpfk.org` cold
response) and cannot be sped up client-side.

**File:** `lib/services/metadata_service.dart`.

**DESIGN DECISION — no metadata caching (do not add):** A stale-while-revalidate cache
(show the last show instantly on launch) was explicitly REJECTED. WBAI is **live radio**:
the displayed metadata must ALWAYS be the current feed, never previous/stale content.
The ~7s cold load showing a placeholder is acceptable; showing yesterday's show is not.

**NOTE on the API URL:** WBAI currently points its metadata fetch at KPFK's endpoint
(`https://confessor.kpfk.org/playlist/_pl_current_ary.php`) as an intentional
PLACEHOLDER until WBAI's own metadata feed is ready. Do NOT "fix" this URL.

---

## 3. Notification: single play/pause control (ported from KPFK)

**Symptom:** WBAI's notification/lock-screen showed TWO controls — play/pause AND a
redundant stop ("X") button.

**Fix:** removed `MediaControl.stop` / `MediaAction.stop` from the three PlaybackState
construction sites in the handler and changed `androidCompactActionIndices` from
`[0, 1]` to `[0]`. Now only one play/pause button shows. `stop()` still exists (it's what
`onTaskRemoved` calls to clear the notification on app close) — there's just no stop
button in the tray.

**File:** `lib/services/audio_service/wbai_audio_handler.dart`
(`_broadcastState`, `_updateMediaSession`, and the force-clean/reset block).

---

## 4. Lock-screen + notification fixes ported from KPFK (code-complete)

All ported into `wbai_audio_handler.dart` / `main.dart` / `AndroidManifest.xml`.
Full root-cause writeups live in KPFK's `docs/lock-screen-bug.md` and
`docs/android-build.md`. Summary:

| Fix | What/why |
|-----|----------|
| **STATE_NONE remap** (lock-screen art blank on play) | `setAudioSource` drops the player to `idle` → audio_service pushes MediaSession `STATE_NONE` → Samsung's lock-screen widget removes the whole session (art+metadata blank). While a `_rebuildingSource` flag is set, `_broadcastState` reports `loading` instead of `idle` so the session never goes NONE. |
| **`_rebuildingSource` null-push guard** | keeps the MediaItem shown through the rebuild's transient idle. |
| **artUri preserve** | internal `_updateMediaItem` no longer drops the artUri (it ran on play and blanked the lock-screen image). |
| **MediaItem dedup** (`_lastPushedMediaSignature`) | skip redundant identical `mediaItem.add()` so audio_service doesn't re-decode the artwork bitmap (Samsung lock-screen flicker). |
| **abort-during-load guard** (`_isAbortError`) | media button pressed while loading → `PlatformException(abort)` is a deliberate platform stop, not a network error; don't trigger the reconnect storm. |
| **`onTaskRemoved()` → `stop()`** | clears the notification when the app is swiped from recents (manifest `stopWithTask` alone is unreliable for a foreground media service). |
| **`androidStopForegroundOnPause: false`** (+ `androidNotificationOngoing: false`) in `main.dart` | keeps the service foreground through pause so `onTaskRemoved` fires reliably whether playing OR paused (close-while-paused otherwise orphaned the notification). |
| **`android:stopWithTask="true"`** on the AudioService in `AndroidManifest.xml` | belt-and-suspenders service teardown on task removal. |

**Status:** code-complete and `flutter analyze`-clean. These were verified on device for
KPFK; on WBAI they have had general device exposure during this session but were not run
through the full dedicated pass (lock-screen pause→play art hold; close-while-playing and
close-while-paused notification clear). Do that focused pass when convenient.

---

## Diagnosis lesson (applies to all of the above)

`flutter run` logs only carry `flutter`/skia/codec tags. The decisive evidence for the
hard bugs — `vol.MediaSessions: Removing KPFK`, `MediaSessionRecord: setPlaybackState`,
`ActivityManager: …remove task`, `Choreographer: Skipped N frames`, and real
metadata-API timing — only appears in full `adb logcat`. Capture native device logs
before theorizing. (Also: debug builds on this 2016 device are much slower than release —
don't over-read debug-build jank.)
