# Feature: Stream Notice (audio unavailable)

**Status:** Shipped (KPFK + WBAI) · **Added:** 2026-07-26 · **Reworked:** 2026-08-14

## What it does
When audio can't play, the app shows one friendly, full-screen notice. It stays
on screen until the listener acts on it. There are **two variants**, chosen by
what actually went wrong:

**1. Server outage** (`StreamNoticeKind.outage`) — Icecast down, mount missing,
dead `.m3u`, confirmed by a health probe.

> **We'll be right back**
> Our live stream is temporarily offline. This is usually brief — please check
> back in a little while and it should be up and running.
> _[ Got it ]_

**2. Connection fault** (`StreamNoticeKind.connection`) — we couldn't reach the
stream but the server is *not* confirmed down: a network blip, captive-portal
Wi-Fi doing TLS interception, reconnect exhausted against a server that probes
healthy, or a player error we couldn't classify.

> **Can't reach the stream**
> We couldn't connect to the live stream. Check your internet connection, then
> try again.
> _[ Try again ]_  ·  _Dismiss_

The split matters: telling someone "we'll be right back" when *their* Wi-Fi is
the problem sends them away to wait for a station that was never down.

## Rules
- **One surface. No snackbars, no inline error cards.** A snackbar
  self-dismisses, so the single explanation a listener gets vanishes if they
  looked away — "huh? what was that?". Everything routes to the modal.
- **Retry only where retrying helps.** The outage variant has no retry (the
  station is down; retrying is theatre). The connection variant leads with it,
  plus a muted `Dismiss` so nobody is trapped into retrying to close the notice.
- **Dismissible, and it stays dismissed.** Dismissing latches
  `_noticeDismissed` and halts the reconnect loop, so the notice can't pop
  straight back and the app isn't hammering a dead server.
- **Fresh retry.** Every play attempt clears the latch, the health cache, and
  re-resolves the `.m3u`, so the moment the stream returns the next play works.
- **Raw technical detail is never the headline.** It rides along as
  `StreamNotice.detail` and renders as a small muted line for the curious.
- **Screen readers hear what the screen says** — one announcement per notice,
  matching the visible copy.

## Where it lives (both apps, same structure)
| File | Role |
|---|---|
| `domain/models/stream_notice.dart` | `StreamNotice` + `StreamNoticeKind` |
| `presentation/widgets/stream_notice_modal.dart` | the notice UI, both variants |
| `presentation/bloc/stream_bloc.dart` | `notice` state, `StreamNoticeRaised` / `DismissStreamNotice` |
| `presentation/pages/home_page.dart` | renders the modal, routes dismiss/retry |
| `data/repositories/stream_repository.dart` | classifies the fault, emits on `noticeStream` |
| `test/stream_notice_test.dart` | notice state-machine guards |

## KPFK vs WBAI
Identical except styling: WBAI is theme-aware (light/dark) with the blue accent;
KPFK is dark-only with the brand-red accent (`0xFFE53935`).

## History
See `STREAM_OFFLINE_MODAL_AUDIT.md` for the full audit trail — the three-surface
mess, the `copyWith` null-clear bug, the `AbsorbPointer` dismiss blocker, and
the silent-failure gap that the 2026-08-14 rework closed.
