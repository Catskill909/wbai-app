import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/stream_notice.dart';
import '../theme/app_theme.dart';

/// The single, acknowledged surface for telling a listener why audio isn't
/// playing. There is no snackbar counterpart on purpose — a self-dismissing
/// message is the only explanation the listener gets, and it's gone if they
/// looked away. This stays up until they act on it.
///
/// Two variants, driven by [StreamNoticeKind]:
///  • [StreamNoticeKind.outage] — the station is down. Nothing to retry, so the
///    copy reassures and the single action just acknowledges.
///  • [StreamNoticeKind.connection] — we couldn't reach the stream but the
///    server isn't confirmed down. The listener can often fix this, so the
///    primary action retries, with a muted escape hatch so they aren't trapped
///    into retrying to close the notice.
class StreamNoticeModal extends StatelessWidget {
  final StreamNotice notice;

  /// Close the notice without retrying.
  final VoidCallback onDismiss;

  /// Close the notice and start a fresh play attempt. Only wired to a visible
  /// button for [StreamNoticeKind.connection].
  final VoidCallback onRetry;

  const StreamNoticeModal({
    super.key,
    required this.notice,
    required this.onDismiss,
    required this.onRetry,
  });

  bool get _isOutage => notice.kind == StreamNoticeKind.outage;

  IconData get _icon =>
      _isOutage ? Icons.wifi_tethering_off_rounded : Icons.cloud_off_rounded;

  String get _headline =>
      _isOutage ? "We'll be right back" : "Can't reach the stream";

  String get _body => _isOutage
      ? 'Our live stream is temporarily offline. This is usually brief — '
          'please check back in a little while and it should be up and running.'
      : "We couldn't connect to the live stream. Check your internet "
          'connection, then try again.';

  String get _primaryLabel => _isOutage ? 'Got it' : 'Try again';

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color accent = WBAIColors.blue;

    // Card + text colors adapt to the active theme for correct contrast.
    final Color card = isDark ? const Color(0xFF1C1413) : WBAIColors.white;
    final Color ink = isDark ? WBAIColors.white : WBAIColors.darkBrown;

    // NOTE: the barrier and the card are SIBLINGS in a Stack. The barrier
    // (ModalBarrier) blocks taps to the content behind the notice, while the
    // card stays fully interactive so its buttons receive taps.
    // (A previous version wrapped the whole thing in AbsorbPointer(absorbing:
    // true), which swallowed the button's own taps → the modal was
    // undismissable. Don't reintroduce that.)
    return Stack(
      children: [
        // Scrim that blocks background taps but NOT the card.
        Positioned.fill(
          child: ModalBarrier(
            color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.55),
            dismissible: false,
          ),
        ),
        Center(
          child: Semantics(
            container: true,
            // Announced when the notice appears, so a screen-reader user gets
            // the same explanation a sighted user reads.
            label: '$_headline. $_body',
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Accent badge
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_icon, color: accent, size: 36),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _headline,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.oswald(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _body,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      height: 1.45,
                      color: ink.withValues(alpha: 0.72),
                    ),
                  ),
                  if (notice.detail != null &&
                      notice.detail!.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      notice.detail!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: ink.withValues(alpha: 0.38),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isOutage ? onDismiss : onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _primaryLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  // The retry variant needs a way out that isn't "retry", or
                  // the only way to close the notice is to trigger another
                  // play attempt.
                  if (!_isOutage) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        foregroundColor: ink.withValues(alpha: 0.55),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      child: Text(
                        'Dismiss',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
