# Testing the outage warnings

Two questions matter equally, and the second is the one that gets missed:

1. When something is genuinely wrong, does the listener get told — correctly?
2. When nothing is wrong, does the app stay quiet?

A radio app that cries "we're down" during a routine rebuffer is worse than one
that says nothing at all.

---

## What runs automatically

```bash
flutter test                      # everything
flutter test test/outage_scenarios_test.dart   # the scenario matrix
```

| File | Covers |
|---|---|
| `outage_scenarios_test.dart` | Full bloc-level matrix: which faults raise a notice, which raise **nothing**, dismiss/retry behaviour |
| `audio_server_health_checker_test.dart` | HTTP-level classification: 200 / 404 / 403 / 503 / 5xx / timeout / refused / bad cert / dead `.m3u` |
| `stream_notice_modal_golden_test.dart` | Both variants in **light and dark** (PNGs in `test/goldens/`), and the buttons actually fire |
| `stream_notice_test.dart` | Notice state machine + `copyWith` clearing semantics |
| `bundled_fonts_test.dart` | Every font weight the app asks for is bundled |

The bloc talks to a `StreamSource` interface, so the tests drive the real
`StreamBloc` with a fake source. The real `StreamRepository` builds a just_audio
player in its constructor and can't run headless — but the questions worth
testing are about how the UI reacts to the streams, not about the player.

Refresh goldens after an intentional design change:

```bash
flutter test --update-goldens test/stream_notice_modal_golden_test.dart
```

---

## Fault → what the listener should see

| Fault | Detected by | Listener sees |
|---|---|---|
| Icecast refuses connection | health probe → `serverUnavailable` | **outage** modal, "We'll be right back" |
| Mount returns 404 | health probe → `streamNotFound` | **outage** modal |
| Mount returns 503 (overloaded) | health probe → `serverOverloaded` | **outage** modal |
| Mount returns 403/401 | health probe → `authenticationError` | **outage** modal |
| `.m3u` host down / returns 5xx | playlist fetch fails | **outage** modal |
| `.m3u` present but contains no stream URL | `M3UParser` returns null | **outage** modal |
| Probe times out | `connectionTimeout` | **outage** modal |
| Captive-portal Wi-Fi (TLS interception) | `NetworkConnectivityException` | **connection** modal, "Can't reach the stream" + Try again |
| Reconnect exhausted, server probes healthy | `_onPlayerError` else-branch | **connection** modal |
| No network at all (airplane mode) | `ConnectivityCubit` | `NetworkLostAlert` — *not* the notice modal |
| Slow but healthy server | watchdog probes, finds it healthy | **nothing** — keeps waiting |
| Rebuffering mid-stream | — | **nothing** |
| Metadata fetch fails while audio plays | — | **nothing** (logged only) |

The outage/connection split matters: telling a listener "we'll be right back"
when *their* hotel Wi-Fi is the problem sends them away to wait for a station
that was never down.

---

## Reproducing on a real device

### Server outages — point the app at a mock

`StreamConstants.streamUrl` is the only thing to change. Run a throwaway server
and edit that constant to `http://<your-mac-lan-ip>:8000/wbai.m3u`.

```bash
mkdir -p /tmp/fakestream && cd /tmp/fakestream
printf '#EXTM3U\nhttp://<your-mac-lan-ip>:8000/mount\n' > wbai.m3u
python3 -m http.server 8000
```

| To simulate | Do this |
|---|---|
| Healthy | add a `mount` file with any bytes — expect **no modal** |
| Mount 404 | leave `mount` absent — expect **outage** modal |
| `.m3u` host down | stop the server — expect **outage** modal |
| Dead playlist | `echo "garbage" > wbai.m3u` — expect **outage** modal |
| 503 / 500 | serve via a tiny handler returning that status — expect **outage** modal |

The device and Mac must be on the same network, and iOS needs a plain-HTTP
exception for the mock host.

### Network faults

| To simulate | Do this |
|---|---|
| No network | Airplane Mode → `NetworkLostAlert`, play button disabled |
| Recovery | Airplane Mode off → alert clears, any stale notice clears, play works |
| Mid-stream drop | play, then Airplane Mode on for ~30s, then off |
| Captive portal | join a hotel/airport network without logging in, or use Charles with SSL proxying and an untrusted root |

### The quiet cases — the ones worth being fussy about

Run these against the **real** stream and confirm **no modal ever appears**:

- Cold launch → press play → audio starts.
- Play, pause, play again several times.
- Play for 10+ minutes through natural rebuffering.
- Background the app for a few minutes, return, keep playing.
- Let a show change happen (metadata refresh) while playing.

### Forcing a notice without an outage

Fastest way to eyeball both variants on-device — temporarily, in `home_page.dart`:

```dart
// DEBUG ONLY — remove before release.
context.read<StreamBloc>().add(
  StreamNoticeRaised(const StreamNotice.connection()),
);
```

Never hardcode a notice into the bloc's **initial state**: it renders before
anything can clear it and the app launches into an undismissable modal.

---

## Known gaps

- The skipped smoke test in `widget_test.dart` needs a device/emulator or
  platform-channel mocks; `audio_service` / `AudioSession` can't init headless.
- Nothing automated covers the lock screen or notification tray during an
  outage — that's device-only.
- Goldens are host-rendered; treat small antialiasing diffs as noise, not
  regressions.
