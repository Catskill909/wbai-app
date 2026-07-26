# Stream-Offline Modal — Full Flow, Fixes & Code Audit

**Date:** 2026-07-26 · **Apps:** WBAI + KPFK (identical template, same fixes)
**Trigger:** A real Icecast outage went up-and-down repeatedly, exposing modal
dismissal + snackbar bugs. This doc records the end-to-end flow, the fixes, the
audit findings, and a troubleshooting checklist for if it recurs.

---

## 1. What the user sees
- **Live outage** → full-screen `AudioServerErrorModal`: "We'll be right back",
  friendly copy, brand-accent badge + "Got it" button. The raw technical reason
  (e.g. "Stream not found on server") appears only as a tiny muted detail line.
- **Transient blip (no modal)** → a floating snackbar: "Stream unavailable —
  please try again shortly" with a Retry action.
- Never both at once.

## 2. End-to-end flow
```
Icecast down
  └─ StreamRepository._handleServerError(healthResult)     [stream_repository.dart]
       ├─ _resetAudioControlsForServerError()  (clear lockscreen/controls)
       ├─ AudioStateManager().handleServerError(...)
       ├─ _serverErrorController.add(errorMessage)   ── serverErrorStream ─┐
       └─ _updateState(StreamState.error)            ── stateStream ──┐    │
                                                                      │    │
StreamBloc._initializeSubscriptions() listens to both:               │    │
  stateStream(error)  → UpdatePlaybackState(error,                   │    │
                          errorMessage:'Stream playback error',      │    │
                          isServerError:false)  ◄────────────────────┘    │
  serverErrorStream(msg) → ServerErrorOccurred(msg)  ◄────────────────────┘

  _onServerErrorOccurred → showServerErrorModal:true,  errorMessage:msg
  _onUpdatePlaybackState → guarded: if modal already up & !isServerError,
                            only updates playbackState (won't clobber modal)

home_page BlocListener:
  if showServerErrorModal → hideCurrentSnackBar()   (kill any raced snackbar)
  if errorMessage!=null && !showServerErrorModal → show snackbar

Dismiss ("Got it") → ClearServerError
  _onClearServerError → repo.clearServerError() (emits serverErrorStream(null)),
                        showServerErrorModal:false, errorMessage:null
```

Reconnect: on a server-confirmed-down the audio handler's reconnect loop is
**halted** (`haltReconnect()`), so the modal does not re-fire on a loop. It only
returns if the user presses play/retry again and the stream is still down.

## 3. Bugs found & fixed (this session)
### Bug A — modal/snackbar wouldn't clear after "Got it"
`StreamBlocState.copyWith` used `errorMessage ?? this.errorMessage`, so
`copyWith(errorMessage: null)` in `_onClearServerError` / `_onStartStream`
**silently kept the stale message**. After dismiss, `errorMessage` was still
non-null, so the guarded snackbar re-appeared.
**Fix:** `_noUpdate` sentinel default on the `errorMessage` param — an explicit
`null` now truly clears; an omitted arg still leaves it unchanged.
(`presentation/bloc/stream_bloc.dart`)

### Bug B — snackbar stranded behind the modal
Two channels fire for one outage. If `UpdatePlaybackState(error)`
(`isServerError:false`) arrives *before* `ServerErrorOccurred`, the snackbar
shows first, then the modal covers it → a snackbar trapped behind the modal.
**Fix:** `home_page.dart` calls `hideCurrentSnackBar()` whenever
`state.showServerErrorModal` is true, killing any snackbar that raced ahead.

### Earlier this session (UI/UX rebuild)
- Modal rebuilt: self-styled (no dependence on the light-mode `Colors.black`
  text styles that had rendered black-on-dark = invisible), theme-aware on WBAI
  (dark-only red accent on KPFK), friendly copy, raw error demoted to detail.
- Snackbar gated on `!showServerErrorModal` + friendly copy + high contrast.

## 4. Audit findings (verified sound)
- **No infinite modal loop.** `_handleServerError` is reached only from the
  connecting watchdog and the reconnect-exhausted classifier, and it halts
  reconnect. Repeated modals during a real outage require repeated user play
  attempts — correct behavior.
- **copyWith sentinel is safe for all callers.** The only explicit `null`
  passes are `_onStartStream` and `_onClearServerError`, both of which *intend*
  to clear. All other callers pass a String or omit the arg.
- **Modal can't be clobbered.** `_onUpdatePlaybackState` early-returns (state
  only) while the modal is up and the update isn't a server error.
- **Dismiss fully resets:** `ClearServerError` clears repo state
  (`serverErrorStream(null)`), `showServerErrorModal`, and `errorMessage`.

## 5. If it recurs — troubleshooting checklist
1. **Modal won't dismiss / re-appears instantly without pressing play.**
   Check `_serverErrorController` isn't being re-emitted by an un-halted
   reconnect. Confirm `haltReconnect()` fires on server-down
   (`wbai_audio_handler.dart`). Verify `copyWith` still has the `_noUpdate`
   sentinel (a refactor could reintroduce `errorMessage ?? this.errorMessage`).
2. **Snackbar behind the modal.** Confirm the `if (showServerErrorModal)
   hideCurrentSnackBar()` guard is still first in the BlocListener.
3. **Modal text invisible again.** Someone reused `AppTextStyles.showTitle`/
   `bodyMedium` (both `Colors.black`) on the dark card — the modal must stay
   self-styled.
4. **Both modal + snackbar show.** The `!state.showServerErrorModal` guard on
   the snackbar was removed.
5. **Reproduce without a real outage:** dispatch `ServerErrorOccurred('test')`
   to the `StreamBloc`. **Never** hardcode `showServerErrorModal:true` into the
   initial `StreamBlocState` — it traps the user in an undismissable modal.

## 5b. Deep audit v2 (2026-07-26, live dead-`.m3u` outage)
A second real outage — the configured mount's `.m3u` resolves to a dead direct
URL (404) — exposed that the first fixes weren't enough. **Root architectural
mess: one outage was surfaced through THREE UI surfaces fed by TWO redundant
data channels.**

`_handleServerError()` fires both:
- `serverErrorStream.add(msg)` → `ServerErrorOccurred` → `showServerErrorModal`
- `_updateState(StreamState.error)` → generic bridge → `errorMessage =
  'Stream playback error occurred'`

Three surfaces consumed them:
1. Modal — `if (showServerErrorModal)` ✓
2. Snackbar — `if (errorMessage != null && !showServerErrorModal)` (races ahead)
3. **Inline error `Card`** in the body — `if (errorMessage != null)`, *no modal
   guard* → showed the redundant string behind the modal.

Plus **the "can't dismiss" bug**: nothing latched the dismissal. On a
continuously-erroring dead stream the reconnect loop + `_onPlayerError` kept
calling `_handleServerError`, re-emitting `serverErrorStream`, so the modal
popped straight back after "Got it". `clearServerError()` never halted reconnect.

### Fix — single source of truth + dismiss latch
| File | Change |
|---|---|
| `stream_bloc.dart` | Generic error bridge no longer attaches the noise string `'Stream playback error occurred'` — outages carry their real message via `ServerErrorOccurred`. Kills the snackbar + inline-card noise at the source. |
| `home_page.dart` | Inline error `Card` now guarded with `&& !state.showServerErrorModal`. (Snackbar keeps its guard + `hideCurrentSnackBar`.) |
| `stream_repository.dart` | New `_serverErrorDismissed` latch: `clearServerError()` sets it **and** calls `_audioHandler.haltReconnect()`; `_handleServerError()` early-returns while latched; `play()` clears it. → "Got it" sticks; a fresh play can still surface a new outage. |

Net: the modal is the **single** authoritative outage UI. Snackbar/inline-card
only appear for non-server action failures ('Failed to play/pause/…'), which
never coincide with the modal.

## 5c. Deep audit v3 (2026-07-26) — THE real dismiss blocker: AbsorbPointer

After v2 the snackbar/card were gone but **the modal still would not dismiss**.
The latch/reconnect work was correct but was never the cause. The actual bug:

> `AudioServerErrorModal` wrapped its **entire** subtree — including the
> "Got it" `ElevatedButton` — in `AbsorbPointer(absorbing: true)`.
> `AbsorbPointer` swallows pointer events for its whole subtree, so the button
> **never received the tap**. The modal was structurally undismissable.

This was in the original modal and survived the redesign. The `AbsorbPointer`
was meant to block taps to the content *behind* the modal, but wrapping the
interactive card in it killed the card's own taps too.

### Fix
Rebuilt the modal as a `Stack` of **siblings**:
- `Positioned.fill(ModalBarrier(...))` — blocks background taps, `dismissible:
  false` (must use the button).
- `Center(card)` — on top, fully interactive → "Got it" works.

### Belt-and-suspenders (also this pass)
- `_handleServerError()` re-checks `_serverErrorDismissed` **after** its
  `await _resetAudioControlsForServerError()` — closes the async race where the
  user dismisses mid-handling and a stale in-flight error re-raises the modal.

### "Poll fresh each attempt" (user request) — already satisfied
Each play after dismiss is a clean poll: `clearServerError()` calls
`AudioServerHealthChecker.clearCache()` (no stale health verdict) and halts
reconnect; `play()` clears the latch, and the handler rebuilds the source and
**re-resolves the `.m3u` fresh** every attempt (no caching). So once the button
works, the play button genuinely re-probes the server each press.

**Lesson for next time the modal "won't dismiss":** check the widget tree for an
`AbsorbPointer`/`IgnorePointer` around the button *before* auditing state flow.

## 6. Files touched
- `presentation/widgets/audio_server_error_modal.dart` — modal rebuild
- `presentation/bloc/stream_bloc.dart` — copyWith sentinel
- `presentation/pages/home_page.dart` — snackbar gate + hide-behind-modal
- `stream-offline-modal.md` (root) — short changelog

`flutter analyze` clean on all changed files in both apps.
