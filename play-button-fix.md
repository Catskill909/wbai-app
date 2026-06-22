# Play Button / Network / Server-Down Fixes — WBAI

These fixes were developed and verified on the **KPFK** sister app and ported
here (the two apps share the same template). See the KPFK repo's
`play-button-fix.md` for the full root-cause audit and research notes. WBAI was
the identical pre-fix baseline, so every bug applied.

## What was broken (all confirmed present in WBAI before this change)
- **Airplane Mode on → off froze the whole app.** Offline modal (`NetworkLostAlert`
  is a full-screen `AbsorbPointer`) only clears when `isOnline` flips true, but
  connectivity was a single 1.5s probe that only re-checks on a transport-change
  event — which doesn't fire on Airplane-off → latched offline forever.
- **Airplane off → play button dead.** Even once the modal cleared, the iOS
  AVPlayer item was dead (just_audio #1277) and recovery did nothing to audio.
- **"Needs reboot" after a failed play.** Health checker cached *failures* in a
  static field for 30s.
- **~2s delay on play** from a blocking pre-flight health GET.
- **Server-down was silent** — the server-error modal was unreachable
  (`isServerError` was never set true) and reconnect retried forever.

## Fixes applied (mirrors KPFK phases 1–10)
| Area | Change |
|---|---|
| `audio_server_health_checker.dart` | Never cache failures; positive cache 30s→5s; **resolve `.m3u` → probe the real mount** (future-ready, see below); `debugSetDio` test seam. |
| `stream_repository.dart` | Non-blocking `play()` (connecting-first, no pre-flight); 8s connecting watchdog; `serverErrorStream`; classify player errors (mid-stream drop) → modal. |
| `wbai_audio_handler.dart` | Reconnect gate (`haltReconnect`), bounded reconnect + exponential backoff (2/4/8/16s, cap 30s), `onError` on `playbackEventStream`, surface error when exhausted. |
| `stream_bloc.dart` | `ServerErrorOccurred` event wires `serverErrorStream` → `showServerErrorModal`; guard so the generic error bridge can't clobber it. |
| `connectivity_service.dart` | Resilient internet probe: 3s timeout, 3 retries. |
| `connectivity_cubit.dart` | Recovery poll (3s) so offline can't latch; all updates routed through `_applyConnectivity`; **cold-reset audio on recovery** (fixes dead AVPlayer). |
| `main.dart` | Cross-platform `_AppResumeObserver`: clear health cache + re-check connectivity on resume. |
| `home_page.dart` | Spinner clears on settled states (gated by `_sawPlaybackProgress`); spinner shows during connecting/buffering (reconnect is visible). |

## WBAI-specific note: M3U switchover readiness
WBAI currently streams a **direct URL** (`streaming.wbai.org/wbai_verizon`), so
the "probed the playlist host instead of Icecast" bug did **not** apply. But the
health checker now resolves `.m3u` playlists to the direct mount before probing
(non-`.m3u` URLs pass through unchanged). **When the station switches
`StreamConstants.streamUrl` to an `.m3u`, no code change is needed** — server-down
detection will automatically probe the real Icecast mount. The audio handler's
`_resolveStreamUrl` already handles `.m3u` playback the same way.

## Tests (terminal, no device / no server control needed)
- `test/m3u_parser_test.dart`
- `test/audio_server_health_checker_test.dart` — direct-URL healthy/down, **M3U
  host down**, **Icecast mount down**, 404 (via injected Dio adapter).
- `test/reconnect_backoff_test.dart`
- Run: `flutter test` → 15 pass. `widget_test.dart` smoke test is `skip:true`
  (needs audio_service platform channels — device/integration only).

## Device test checklist
- Play / pause / re-play.
- Background → resume → play works immediately.
- Airplane Mode on → off (several times): modal clears, reconnect + spinner work.
- (If possible) block the stream host at the router to see the server modal.
