import 'package:flutter/foundation.dart';

import '../constants/stream_constants.dart';

/// Debug-only redirection of the stream URL, so outages can be rehearsed
/// WITHOUT touching the station's live stream.
///
/// The station broadcasts to real listeners; taking Icecast down to see what
/// the app does is not an option. Instead we point the *app* somewhere broken.
/// Every preset below runs the genuine pipeline — `.m3u` resolution, the health
/// probe, error classification, the notice — so what you see on screen is the
/// real behaviour, not a mocked-up modal.
///
/// **Inert in release builds.** [url] is hard-gated on [kDebugMode], so a
/// release binary always resolves to [StreamConstants.streamUrl] no matter what
/// was stored, and the debug panel is never built.
class DebugStreamOverride {
  DebugStreamOverride._();

  static String? _url;
  static String? _activeLabel;

  /// The override, or null in release builds / when unset.
  static String? get url => kDebugMode ? _url : null;

  /// Name of the active preset, for the debug UI.
  static String? get activeLabel => kDebugMode ? _activeLabel : null;

  /// What the app should actually play. Every consumer reads this.
  static String get effectiveUrl => url ?? StreamConstants.streamUrl;

  static bool get isOverridden => url != null;

  static void apply(DebugOutagePreset preset) {
    if (!kDebugMode) return;
    _url = preset.url;
    _activeLabel = preset.label;
  }

  static void clear() {
    _url = null;
    _activeLabel = null;
  }
}

/// A way to make the stream unreachable that costs nothing to set up — no mock
/// server, no config, no impact on the live stream.
class DebugOutagePreset {
  final String label;
  final String description;

  /// null for [live] — meaning "no override".
  final String? url;

  /// What the listener should see. Stated so a run can be judged pass/fail.
  final String expected;

  const DebugOutagePreset({
    required this.label,
    required this.description,
    required this.url,
    required this.expected,
  });

  static const live = DebugOutagePreset(
    label: 'Live stream (normal)',
    description: 'The real WBAI stream.',
    url: null,
    expected: 'Audio plays. NO modal — this is the false-alarm check.',
  );

  /// Port 9 is the discard port: nothing listens, so the connection is refused
  /// instantly. No server to run, and it never leaves the device.
  static const refused = DebugOutagePreset(
    label: 'Server refuses connection',
    description: 'Icecast down / not listening (localhost:9).',
    url: 'http://127.0.0.1:9/wbai_verizon',
    expected: 'OUTAGE modal — "We\'ll be right back".',
  );

  /// 10.255.255.1 is non-routable, so the connection hangs until it times out.
  /// Slowest preset — allow ~10s for the watchdog and probe.
  static const timeout = DebugOutagePreset(
    label: 'Server times out',
    description: 'Unreachable host — takes ~10s by design.',
    url: 'http://10.255.255.1/wbai_verizon',
    expected: 'OUTAGE modal after the watchdog fires.',
  );

  static const notFound = DebugOutagePreset(
    label: 'Mount not found (404)',
    description: 'The Icecast mount name is wrong or gone.',
    url: 'https://streaming.wbai.org/this-mount-does-not-exist',
    expected: 'OUTAGE modal — "stream not found on server".',
  );

  // No dead-playlist preset here: WBAI streams a direct Icecast mount rather
  // than an .m3u, so the playlist-resolution path never runs.
  static const all = <DebugOutagePreset>[
    live,
    refused,
    timeout,
    notFound,
  ];
}
