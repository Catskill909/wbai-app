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

---

## Deep audit v4 (2026-08-14) — silent failures, and one surface for real

A pre-release audit of the whole notification path found the previous design was
still telling the listener **nothing at all** for a large class of failures.

### Bug D — the silent failure (the important one)
v2 removed the `'Stream playback error occurred'` string from the generic error
bridge, and the `_noUpdate` sentinel made `copyWith` *explicitly clear*
`errorMessage` on every playback-state tick. Together those meant `errorMessage`
was only ever non-null while the modal was already up, or from the bloc's own
try/catch — and since `AudioHandler.play()` swallows its exceptions instead of
rethrowing, `_repository.play()` almost never throws. **The snackbar was
effectively unreachable.**

Concretely, three paths set the error state and emitted no message whatsoever:
`_onConnectingTimeout`'s `NetworkConnectivityException` catch,
`_handlePlaybackFailure`'s tail, and `_onPlayerError` (both its network catch
and its "server probes healthy" branch). Symptom: tap play → spinner runs 8s →
spinner stops → nothing. No modal, no message, no explanation.

Worst realistic trigger: captive-portal Wi-Fi (hotel/airport) doing TLS
interception → `DioExceptionType.badCertificate` → `NetworkConnectivityException`.
`NetworkLostAlert` doesn't cover it either, because `ConnectivityService`'s probe
accepts any 2xx/3xx and a captive portal's 200 login page reads as "online".

**Fix:** every one of those paths now emits `StreamNotice.connection()`.

### The rework
- **No snackbars, anywhere.** They self-dismiss; the one explanation a listener
  gets disappears if they looked away. Deleted.
- **Inline error `Card` deleted.** It duplicated the snackbar's text *and* its
  Retry action, and it sat inside the home Column **without being counted in
  `spaceLeftForImage`**, so it shrank the station image whenever it appeared.
- **`errorMessage` deleted from bloc state.** With the snackbar and card gone it
  had no consumer, which retires the whole `_noUpdate` sentinel class of bugs
  (Bug A). State now carries a single `StreamNotice? notice`; `copyWith` spells
  clearing out as `clearNotice: true` rather than a null sentinel.
- **Two channels collapsed to one.** `serverErrorStream` + the generic state
  bridge → one `noticeStream` carrying `StreamNotice?`. `UpdatePlaybackState`
  no longer carries error text at all, so it *structurally cannot* clobber a
  notice — the guard that used to do that job is gone.
- **Two variants** (`outage` / `connection`) so a network fault isn't
  mislabelled as a station outage. Retry appears only on `connection`.

### Adjacent bugs found and fixed in the same pass
- `retry()` called `stop()` (which halts metadata polling) and `play()` never
  restarted it → show name/host froze after every retry. Now calls
  `restartMetadataService()`. Newly important: "Try again" is a real button now.
- Metadata `onError` did `_updateState(StreamState.error)` → a transient
  show-info fetch failure knocked the play button out of its playing state
  mid-stream. Now logs only.
- `stopAndColdReset` didn't clear `_awaitingPlay` (WBAI already did). Latched
  true, the next `ready && !playing` maps to `buffering` → a spinner that never
  resolves. Ported.
- WBAI `widget_test.dart` failed in `setUpAll` (SharedPreferences has no
  platform channel headless) — whole suite red. Added
  `SharedPreferences.setMockInitialValues`.

### Verified
`flutter analyze` clean and `flutter test` green in both apps (KPFK 23 passed,
WBAI 35 passed, 1 skipped each — the pre-existing device-only smoke test).
New `test/stream_notice_test.dart` guards the notice state machine.

### If it recurs — checklist
1. Notice won't dismiss → check `haltReconnect()` fires and `clearNotice: true`
   is used (never `notice: null`, which `copyWith` treats as "leave unchanged").
2. Notice never appears for a network fault → check the emit calls in
   `_emitConnectionNotice` callers; that's the silent-failure regression.
3. Two messages at once → something reintroduced a snackbar or inline card.
   Don't. See `no-snackbars` in the feature doc.
4. Reproduce without an outage: emit `StreamNotice.connection()` on
   `noticeStream`. **Never** hardcode a notice into the bloc's initial state.
---

## Deep audit v5 (2026-08-14) — scenario coverage, and a live misclassification

Writing the scenario matrix immediately caught a real bug.

### Bug E — every 5xx blamed the listener's internet
`checkServerHealth` probed with `validateStatus: (status) => status != null &&
status < 500`, so Dio threw on any 5xx *before* the status-code branching ran.
That made two branches of the classifier unreachable dead code — `statusCode ==
503` and the generic 5xx case — and routed every 5xx into
`NetworkConnectivityException`, i.e. the **connection** notice.

Net effect: an overloaded Icecast returning **503**, one of the most ordinary
outage modes a radio station has, told the listener to check their own internet
connection while the station was the thing that was down. Same for a 5xx from
the `.m3u` host. Fixed by accepting every status so the classifier's own
branches decide, in both the mount probe and the playlist fetch.

### Testability seam
`StreamBloc` now depends on a `StreamSource` interface that `StreamRepository`
implements. Production wiring is unchanged; it exists so the bloc can be driven
by a fake, since the real repository builds a just_audio player in its
constructor and cannot run headless. This is what makes the "stays quiet when
nothing is wrong" half of the matrix testable at all.

### Coverage added
- `outage_scenarios_test.dart` — 17 scenarios, split into "the listener IS
  warned" and "the listener is NOT warned". The second group is the point:
  healthy start, rebuffering blips, pause/resume, bare error states and metadata
  updates must all raise nothing.
- `audio_server_health_checker_test.dart` — 503, 403, timeout, playlist 5xx,
  captive-portal bad certificate, and proof that a failure is never cached.
- `stream_notice_modal_golden_test.dart` — both variants rendered to PNG with
  real Oswald/Poppins and the MaterialIcons badge, plus tap tests guarding the
  old `AbsorbPointer` regression.
- `widget_test.dart` — moved `setupServiceLocator()` out of `setUpAll` and into
  the (skipped) test body. `setUpAll` runs even for skipped tests, so it was
  spinning up audio_service/AudioSession for nothing and intermittently failing
  the whole suite under parallel load.

See `TESTING_outage_scenarios.md` for the fault→notice table and the recipes for
reproducing each outage on a device.
