import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// A friendly, high-contrast modal shown when the live stream is unavailable.
///
/// Leads with reassuring "check back later" messaging instead of surfacing raw
/// technical errors. The optional [customMessage] is shown as a small, muted
/// detail line for the curious — never as the headline.
class AudioServerErrorModal extends StatelessWidget {
  final VoidCallback onDismiss;

  /// Raw technical detail (e.g. "Stream not found on server"). Optional and
  /// rendered subtly; the user-facing explanation is always friendly.
  final String? customMessage;

  const AudioServerErrorModal({
    super.key,
    required this.onDismiss,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color accent = WBAIColors.blue;

    // Card + text colors adapt to the active theme for correct contrast.
    final Color card = isDark ? const Color(0xFF1C1413) : WBAIColors.white;
    final Color ink = isDark ? WBAIColors.white : WBAIColors.darkBrown;

    // NOTE: the barrier and the card are SIBLINGS in a Stack. The barrier
    // (ModalBarrier) blocks taps to the content behind the modal, while the
    // card stays fully interactive so the "Got it" button receives taps.
    // (A previous version wrapped the whole thing in AbsorbPointer(absorbing:
    // true), which swallowed the button's own taps → the modal was
    // undismissable.)
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
                  child: const Icon(
                    Icons.wifi_tethering_off_rounded,
                    color: accent,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "We'll be right back",
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
                  "Our live stream is temporarily offline. This is usually "
                  "brief — please check back in a little while and it "
                  "should be up and running.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    height: 1.45,
                    color: ink.withValues(alpha: 0.72),
                  ),
                ),
                if (customMessage != null && customMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    customMessage!,
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
                    onPressed: onDismiss,
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
                      'Got it',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
