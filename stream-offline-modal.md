# Stream-Offline Modal Redesign — WBAI

**2026-07-26.** Reworked the "audio server unavailable" experience into a
friendly, high-contrast, theme-aware notice. Ported to the KPFK sister app the
same day (see KPFK's `stream-offline-modal.md`).

## Why
The old modal (`AudioServerErrorModal`) reused `AppTextStyles.showTitle` /
`bodyMedium`, both `Colors.black` since the light-mode migration, painted on a
dark `0xFF161616` card — so on a live outage the title/body were **invisible**
(black-on-dark). It also surfaced the raw technical string
("Stream not found on server") as the headline, and a **second** red snackbar
fired the same technical error at the same time → the user was told twice, badly.

## What changed
| File | Change |
|---|---|
| `presentation/widgets/audio_server_error_modal.dart` | Full rebuild. Self-styled (no dependence on the black theme text styles), **theme-aware**: white card + dark-brown ink in light mode, `0xFF1C1413` card + white ink in dark mode. Blue brand accent badge (`wifi_tethering_off`), friendly headline **"We'll be right back"** + reassuring "check back in a little while" copy, full-width "Got it" button. Raw `customMessage` is kept only as a tiny muted detail line, never the headline. |
| `presentation/pages/home_page.dart` | Snackbar now **suppressed while the modal is showing** (`!state.showServerErrorModal`) so the outage isn't announced twice. When it does fire (transient blips, no modal), it's explicit high-contrast: dark-brown bg, white friendly copy ("Stream unavailable — please try again shortly"), blue Retry action; `hideCurrentSnackBar()` first to avoid stacking. |

## 2026-07-26 (later) — real-outage fixes
A genuine stream outage exposed two bugs:

- **Modal/snackbar wouldn't clear.** `StreamBlocState.copyWith` used
  `errorMessage ?? this.errorMessage`, so `copyWith(errorMessage: null)` in
  `_onClearServerError` / `_onStartStream` **kept the stale message**. After
  "Got it", `errorMessage` stayed non-null → the guarded snackbar re-fired.
  Fixed with a `_noUpdate` sentinel default on the `errorMessage` param so an
  explicit `null` truly clears while an omitted arg still leaves it unchanged.
- **Snackbar stranded behind the modal.** The generic
  `UpdatePlaybackState(error)` bridge sets `errorMessage` with
  `isServerError: false` and can arrive *before* `ServerErrorOccurred` raises
  the modal → a snackbar shows, then the modal covers it. `home_page.dart` now
  calls `hideCurrentSnackBar()` whenever `state.showServerErrorModal` is true,
  killing any snackbar that raced ahead.

(Pressing play again during a still-live outage *should* re-show the modal —
that's correct, the stream really is down.)

## Notes
- The modal is invoked from `home_page.dart` when `state.showServerErrorModal`
  is true; dismiss dispatches `ClearServerError`.
- To preview without a real outage, dispatch `ServerErrorOccurred(msg)` to the
  `StreamBloc`. Do **not** hardcode `showServerErrorModal: true` into the bloc's
  initial `StreamBlocState` — that traps the user in an undismissable modal on
  launch.
- `flutter analyze` clean on both changed files.
