# Feature: Stream-Offline Notice

**Status:** Shipped (WBAI + KPFK) · **Added:** 2026-07-26

## What it does
When the live audio stream can't be reached — server down, mount missing, dead
`.m3u`, timeout — the app shows a friendly full-screen notice instead of failing
silently or dumping a technical error:

> **We'll be right back**
> Our live stream is temporarily offline. This is usually brief — please check
> back in a little while and it should be up and running.
> _[Got it]_

- Reassuring, plain-language copy (no jargon). The raw technical reason (e.g.
  "Stream not found on server") appears only as a small muted detail line.
- One accent badge + one primary button. Nothing else competes with it.
- **WBAI:** theme-aware (light card in light mode, dark card in dark mode), blue
  brand accent. **KPFK:** dark card, red brand accent (dark-only app).

## How it behaves
- **Single source of truth.** The outage is shown by the modal *only* — never a
  duplicate snackbar or inline error card at the same time.
- **Dismissible.** "Got it" closes it and it stays closed (does not pop back
  while the stream is still down).
- **Fresh retry.** Each time the user presses play again, the app re-probes the
  server from scratch (health cache cleared, stream URL / `.m3u` re-resolved, no
  stale state) — so as soon as the stream returns, the next play just works.
- **No battery drain behind the modal.** The background reconnect loop is halted
  on dismiss, so the app isn't hammering a dead server.

## Transient vs. outage
- A genuine **server outage** → the full-screen modal (above).
- A one-off **action failure** (e.g. "Failed to play") → a lightweight snackbar
  with a Retry action. These never coincide with the modal.

## Where it lives (both apps, same structure)
- `presentation/widgets/audio_server_error_modal.dart` — the notice UI
- `presentation/bloc/stream_bloc.dart` — `showServerErrorModal` state +
  `ServerErrorOccurred` / `ClearServerError` events
- `presentation/pages/home_page.dart` — renders the modal, routes dismiss
- `data/repositories/stream_repository.dart` — detects the outage
  (`_handleServerError`), the dismiss latch, and fresh-retry reset

## Engineering history / rationale
See `STREAM_OFFLINE_MODAL_AUDIT.md` for the full audit trail (the three-surface
mess, the copyWith null-clear bug, and the `AbsorbPointer` dismiss blocker) and
the troubleshooting checklist for if any of it regresses.
