/// Why audio isn't playing, in terms the UI can present to a listener.
///
/// One notice is shown at a time, through one surface (the modal). There is
/// deliberately no snackbar / inline-card variant: a self-dismissing message is
/// the one explanation the listener gets, and it vanishes if they looked away.
enum StreamNoticeKind {
  /// The station's audio server is confirmed down — Icecast unreachable, mount
  /// missing, dead `.m3u`. Retrying immediately won't help, so the notice asks
  /// the listener to check back rather than offering a retry.
  outage,

  /// We couldn't reach the stream, but the server itself is NOT confirmed down:
  /// a network blip, captive-portal Wi-Fi doing TLS interception, or a player
  /// error we couldn't classify. The listener may well be able to fix this, so
  /// the notice leads with a retry.
  connection,
}

/// A single user-facing notice about playback, and the raw technical reason
/// behind it (shown only as a small muted detail line — never as the headline).
class StreamNotice {
  final StreamNoticeKind kind;

  /// Raw technical detail, e.g. "Stream not found on server". Optional; the
  /// user-facing explanation always comes from [kind], never from this string.
  final String? detail;

  const StreamNotice({required this.kind, this.detail});

  const StreamNotice.outage({String? detail})
      : this(kind: StreamNoticeKind.outage, detail: detail);

  const StreamNotice.connection({String? detail})
      : this(kind: StreamNoticeKind.connection, detail: detail);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamNotice && other.kind == kind && other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, detail);

  @override
  String toString() => 'StreamNotice($kind, detail: $detail)';
}
