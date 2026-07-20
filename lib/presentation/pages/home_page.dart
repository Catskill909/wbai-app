import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/stream_bloc.dart';
import '../../data/repositories/stream_repository.dart';
import '../theme/font_constants.dart';
import 'pacifica_apps_page.dart';
import '../widgets/app_drawer.dart';
import '../widgets/audio_server_error_modal.dart';
import '../widgets/show_info_modal.dart';
import '../bloc/connectivity_cubit.dart';
import '../widgets/donate_webview_sheet.dart';
import '../widgets/sleep_timer_overlay.dart';
import '../bloc/sleep_timer_cubit.dart';
import '../../core/di/service_locator.dart' as di;
import '../../core/services/logger_service.dart';
import '../bloc/theme_cubit.dart';
import '../theme/app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showLocalLoading = false;
  // Becomes true once a play attempt has reached an in-progress state
  // (connecting/loading/buffering). Used so the spinner only clears on a
  // *settled* state (paused/stopped/initial) AFTER real progress — never on
  // the transient old-state emit that fires right when play is dispatched.
  bool _sawPlaybackProgress = false;
  bool _userPressedPause = false; // Track when user pressed pause button
  bool _showInfoModal = false; // Track info modal visibility

  // PHASE 1: Spinner timeout safety mechanism
  Timer? _spinnerTimeoutTimer;
  static const Duration _maxSpinnerDuration = Duration(seconds: 10);

  // Track last announced states to reduce repeated announcements
  StreamState? _lastAnnouncedPlayback;
  String? _lastAnnouncedShow;

  Widget _buildLoadingContainer(String message) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PacificaAppsPage(),
      ),
    );
  }

  // PHASE 1: Spinner timeout safety methods
  void _startSpinnerTimeout() {
    _spinnerTimeoutTimer?.cancel();
    _spinnerTimeoutTimer = Timer(_maxSpinnerDuration, () {
      if (_showLocalLoading && mounted) {
        LoggerService.warning(
            '🔄 SPINNER TIMEOUT: Force reset loading state after ${_maxSpinnerDuration.inSeconds}s');
        setState(() {
          _showLocalLoading = false;
        });
      }
    });
  }

  void _cancelSpinnerTimeout() {
    _spinnerTimeoutTimer?.cancel();
    _spinnerTimeoutTimer = null;
  }

  @override
  void initState() {
    super.initState();
    // Removed auto-clear that was interfering with audio playback
  }

  @override
  void dispose() {
    _cancelSpinnerTimeout();
    super.dispose();
  }

  // PHASE 10: in-progress states where the play button should show a spinner
  // even without a local tap — e.g. a background reconnect after a stream drop.
  bool _isConnectingState(StreamState s) =>
      s == StreamState.connecting ||
      s == StreamState.loading ||
      s == StreamState.buffering;

  // Filled-circle glyph rendered at full button size — the Material behind it
  // is the same color as the page background (white in light, near-black in
  // dark), so the icon's own fill becomes the visible disc and its cut-out
  // triangle reveals the matching background as the "hole". Dark mode is the
  // exact color inverse of light mode at the same size.
  IconData _getPlaybackIcon(StreamState state) {
    switch (state) {
      case StreamState.playing:
        return Icons.pause_circle_filled;
      case StreamState.loading:
      case StreamState.buffering:
        return Icons.play_circle_filled;
      default:
        return Icons.play_circle_filled;
    }
  }

  // Helper function to detect iPad Pro specifically (large tablets)
  // iPad Pro 11" has shortestSide ~834, iPad Pro 12.9" has ~1024
  // Regular iPads and medium tablets have shortestSide ~768 or less
  bool _isLargeTablet(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide > 800; // Only iPad Pro and similar large tablets
  }

  bool _isMediumTablet(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide > 600 &&
        size.shortestSide <= 800; // Regular tablets
  }

  bool _isSmallPhone(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide < 380; // Phones smaller than iPhone XR
  }

  // Measures the rendered height of the metadata text block, matching the
  // widgets below line-for-line. Used ONLY to compute how much room the stacked
  // content needs so the image can shrink as a last resort — never to drive the
  // image size when there IS room. Gap constants must match the text block.
  double _measureMetadataHeight({
    required StreamBlocState state,
    required Size size,
    required bool isSmall,
    required double maxWidth,
  }) {
    double measure(String text, TextStyle style, int maxLines) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      return tp.height;
    }

    if (state.metadata == null) {
      return 20.0 +
          measure('Loading stream information...', AppTextStyles.bodyMedium, 2);
    }

    final cur = state.metadata!.current;
    double h = isSmall ? 16.0 : 20.0; // gap above title
    h += measure(cur.showName, AppTextStyles.showTitleForDevice(size), 2);
    h += 4.0;
    h += measure(cur.time, AppTextStyles.showTimeForDevice(size), 2);
    if (cur.hasSongInfo) {
      h += isSmall ? 8.0 : 10.0;
      h += measure('Song: ${cur.songTitle} - ${cur.songArtist}',
          AppTextStyles.bodyLargeForDevice(size), 2);
    } else if (state.metadata!.next.showName.isNotEmpty) {
      h += isSmall ? 8.0 : 10.0;
      h += measure('Next: ${state.metadata!.next.showName}',
          AppTextStyles.bodyMediumForDevice(size), 2);
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final isOnline =
        context.select<ConnectivityCubit, bool>((c) => c.state.isOnline);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.menu,
              size: _isLargeTablet(context)
                  ? 48
                  : (_isMediumTablet(context)
                      ? 38
                      : (_isSmallPhone(context) ? 26 : 30)),
              color: iconColor,
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Image.asset(
          'assets/images/header.png',
          height: _isLargeTablet(context)
              ? 70
              : (_isMediumTablet(context)
                  ? 60
                  : (_isSmallPhone(context) ? 34 : 40)),
          fit: BoxFit.contain,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              size: _isLargeTablet(context)
                  ? 44
                  : (_isMediumTablet(context)
                      ? 34
                      : (_isSmallPhone(context) ? 22 : 26)),
              color: iconColor,
            ),
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: () => context.read<ThemeCubit>().toggle(),
          ),
          IconButton(
            icon: Icon(
              Icons.radio,
              size: _isLargeTablet(context)
                  ? 48
                  : (_isMediumTablet(context)
                      ? 38
                      : (_isSmallPhone(context) ? 26 : 30)),
              color: iconColor,
            ),
            onPressed: () => _navigateToSettings(context),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<StreamBloc, StreamBlocState>(
          listener: (context, state) {
            // SPINNER DEBUG: Log state changes to understand the flow
            LoggerService.debug(
                '🔄 SPINNER: State changed to ${state.playbackState}, _showLocalLoading: $_showLocalLoading');

            // SPINNER FIX: Clear the spinner once playback settles, so it never
            // outlives the play attempt. We keep it during the in-progress
            // states (connecting/loading/buffering) and only treat a settled
            // state (paused/stopped/initial) as "done" after we've actually
            // seen progress — otherwise the transient old-state emit that fires
            // the moment play is dispatched would clear the spinner too early.
            if (_showLocalLoading) {
              final s = state.playbackState;
              final inProgress = s == StreamState.connecting ||
                  s == StreamState.loading ||
                  s == StreamState.buffering;
              if (inProgress) {
                _sawPlaybackProgress = true;
                LoggerService.debug(
                    '🔄 SPINNER: Keeping spinner - in-progress state is $s');
              } else if (s == StreamState.playing ||
                  s == StreamState.error ||
                  _sawPlaybackProgress) {
                LoggerService.debug('🔄 SPINNER: Clearing spinner - state is $s');
                setState(() {
                  _showLocalLoading = false;
                });
                _sawPlaybackProgress = false;
                _cancelSpinnerTimeout();
              } else {
                LoggerService.debug(
                    '🔄 SPINNER: Keeping spinner - awaiting progress (state $s)');
              }
            }

            // NETWORK RECOVERY: Don't interfere with spinner during legitimate loading
            // The spinner timeout will handle stuck states if needed

            // Reset pause flag when pause completes
            if (_userPressedPause &&
                (state.playbackState == StreamState.paused ||
                    state.playbackState == StreamState.initial)) {
              setState(() {
                _userPressedPause = false;
              });
            }

            // Announce playback state transitions (polite)
            if (_lastAnnouncedPlayback != state.playbackState) {
              _lastAnnouncedPlayback = state.playbackState;
              final dir = Directionality.of(context);
              switch (state.playbackState) {
                case StreamState.playing:
                  SemanticsService.sendAnnouncement(
                      View.of(context), 'Playing WBAI stream', dir);
                  break;
                case StreamState.paused:
                  SemanticsService.sendAnnouncement(
                      View.of(context), 'Stream stopped and reset', dir);
                  break;
                case StreamState.loading:
                  SemanticsService.sendAnnouncement(
                      View.of(context), 'Loading audio', dir);
                  break;
                case StreamState.buffering:
                  SemanticsService.sendAnnouncement(
                      View.of(context), 'Buffering audio', dir);
                  break;
                case StreamState.error:
                  // error announcement happens below via error message if present
                  break;
                default:
                  break;
              }
            }

            // Announce metadata changes (show/song)
            final currentShow = state.metadata?.current.showName;
            if (currentShow != null &&
                currentShow.isNotEmpty &&
                currentShow != _lastAnnouncedShow) {
              _lastAnnouncedShow = currentShow;
              final dir = Directionality.of(context);
              final hasSong = state.metadata!.current.hasSongInfo;
              final msg = hasSong
                  ? 'Now playing ${state.metadata!.current.songTitle} by ${state.metadata!.current.songArtist} on ${state.metadata!.current.showName}'
                  : 'Now playing ${state.metadata!.current.showName}';
              SemanticsService.sendAnnouncement(View.of(context), msg, dir);
            }

            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    state.errorMessage!,
                    style: AppTextStyles.bodyMedium,
                  ),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: 'Retry',
                    onPressed: () {
                      context.read<StreamBloc>().add(RetryStream());
                    },
                  ),
                ),
              );
              // Announce error message for screen readers
              SemanticsService.sendAnnouncement(View.of(context),
                  state.errorMessage!, Directionality.of(context));
            }
          },
          builder: (context, state) {
            return Stack(
              children: [
                // Main content
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmall = _isSmallPhone(context);
                      final isTab =
                          MediaQuery.of(context).size.shortestSide > 600;
                      final sw = constraints.maxWidth;
                      final double hPad = isSmall ? 12.0 : 16.0;
                      // Reserves. bottomReserve only clears the floating corner
                      // donate/alarm buttons (~56px, in the corners, which the
                      // centered play button never reaches) — keeping it large
                      // would starve the image via the clamp below.
                      final double bottomReserve = isSmall ? 40.0 : 48.0;
                      final double topGap = isSmall ? 12.0 : 16.0;
                      final double gapAboveButton = isSmall ? 20.0 : 28.0;
                      final double gapBelowButton = isSmall ? 12.0 : 24.0;

                      // Play button footprint (must match the widget below).
                      final double buttonSize =
                          isSmall ? 90.0 : (isTab ? 150.0 : 120.0);
                      final double buttonMargin = isSmall ? 4.0 : 8.0;
                      final double buttonBlock = buttonSize + buttonMargin * 2;

                      // WIDTH-first image: the size it WANTS whenever there is
                      // room (this is the clamp's UPPER CAP, so it can never be
                      // shrunk by text while space remains). It only shrinks as a
                      // last resort so the stacked content still fits (no scroll).
                      final double bigWidthSize =
                          sw * (isSmall ? 0.8 : (isTab ? 0.72 : 0.85));
                      final double contentW = sw - hPad * 2;
                      final double textBlockH = _measureMetadataHeight(
                        state: state,
                        size: MediaQuery.of(context).size,
                        isSmall: isSmall,
                        maxWidth: contentW,
                      );
                      final double viewportH =
                          constraints.maxHeight - bottomReserve;
                      final double spaceLeftForImage = viewportH -
                          topGap -
                          textBlockH -
                          gapAboveButton -
                          buttonBlock -
                          gapBelowButton;
                      final double logoSize = spaceLeftForImage
                          .clamp(isSmall ? 80.0 : 120.0, bigWidthSize)
                          .toDouble();
                      return SingleChildScrollView(
                        padding: EdgeInsets.only(bottom: bottomReserve),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: viewportH),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(height: topGap),
                              // Station image — WIDTH-based square (logoSize).
                              SizedBox(
                                width: logoSize,
                                height: logoSize,
                                child: GestureDetector(
                                      onTap: state.metadata != null
                                          ? () {
                                              setState(() {
                                                _showInfoModal = true;
                                              });
                                            }
                                          : null,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isDark
                                                ? const Color(
                                                    0x1AFFFFFF) // ~10% white
                                                : const Color(
                                                    0x14000000), // ~8% black
                                            width: isTab ? 1 : 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                  red: 0,
                                                  green: 0,
                                                  blue: 0,
                                                  alpha: 77),
                                              blurRadius: 8,
                                              offset: const Offset(2, 2),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: state.metadata?.current
                                                      .hasHostImage ==
                                                  true
                                              ? Image.network(
                                                  state.metadata!.current
                                                      .hostImage!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    final fallback = state
                                                        .metadata!
                                                        .stationFallbackImage;
                                                    if (fallback != null) {
                                                      return Image.network(
                                                        fallback,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (ctx, e,
                                                                st) =>
                                                            _buildLoadingContainer(
                                                                'Error loading image'),
                                                      );
                                                    }
                                                    return _buildLoadingContainer(
                                                        'Error loading image');
                                                  },
                                                )
                                              : _buildLoadingContainer(
                                                  'Loading stream information...'),
                                        ),
                                      ),
                                    ),
                              ),
                            // Text section — natural height, always below image
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: hPad),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (state.metadata != null) ...[
                                    SizedBox(height: isSmall ? 16 : 20),
                                    Text(
                                      state.metadata!.current.showName,
                                      style: AppTextStyles.showTitleForDevice(
                                              MediaQuery.of(context).size)
                                          .copyWith(color: iconColor),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      state.metadata!.current.time,
                                      style: AppTextStyles.showTimeForDevice(
                                              MediaQuery.of(context).size)
                                          .copyWith(color: iconColor),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (state
                                        .metadata!.current.hasSongInfo) ...[
                                      SizedBox(height: isSmall ? 8 : 10),
                                      Text(
                                        'Song: ${state.metadata!.current.songTitle} - ${state.metadata!.current.songArtist}',
                                        style: AppTextStyles.bodyLargeForDevice(
                                                MediaQuery.of(context).size)
                                            .copyWith(color: iconColor),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ] else if (state.metadata!.next.showName
                                        .isNotEmpty) ...[
                                      SizedBox(height: isSmall ? 8 : 10),
                                      Text(
                                        'Next: ${state.metadata!.next.showName}',
                                        style: AppTextStyles.bodyMediumForDevice(
                                                MediaQuery.of(context).size)
                                            .copyWith(color: iconColor),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ] else ...[
                                    const SizedBox(height: 20),
                                    Text(
                                      'Loading stream information...',
                                      style: AppTextStyles.bodyMedium
                                          .copyWith(color: iconColor),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Breathing between the metadata and the play button.
                            SizedBox(height: gapAboveButton),
                            // Playback Control with Loading State
                            Container(
                              alignment: Alignment.center,
                              margin:
                                  EdgeInsets.symmetric(vertical: buttonMargin),
                              child: Semantics(
                                button: true,
                                enabled: true,
                                label: _showLocalLoading
                                    ? 'Loading audio'
                                    : (state.playbackState ==
                                            StreamState.playing
                                        ? 'Stop stream and reset'
                                        : 'Play stream'),
                                hint: _showLocalLoading
                                    ? null
                                    : 'Double tap to ${state.playbackState == StreamState.playing ? 'stop and reset' : 'play'}',
                                liveRegion: _showLocalLoading,
                                child: Material(
                                  color: isDark
                                      ? WBAIColors.trueBlack
                                      : Colors.white,
                                  shape: const CircleBorder(),
                                  elevation: 0,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: (!isOnline ||
                                            state.playbackState ==
                                                StreamState.loading ||
                                            state.playbackState ==
                                                StreamState.buffering ||
                                            _showLocalLoading)
                                        ? (!isOnline
                                            ? () {
                                                // Network alert will automatically appear via main.dart
                                                return;
                                              }
                                            : null)
                                        : () {
                                            if (state.playbackState ==
                                                StreamState.playing) {
                                              // PAUSE: Set flag to prevent spinner
                                              setState(() {
                                                _userPressedPause = true;
                                              });
                                              context
                                                  .read<StreamBloc>()
                                                  .add(PauseStream());
                                            } else {
                                              // PLAY: Show spinner
                                              LoggerService.debug(
                                                  '🔄 SPINNER: Play button pressed, current state: ${state.playbackState}');
                                              setState(() {
                                                _showLocalLoading = true;
                                                _sawPlaybackProgress = false;
                                                _userPressedPause = false;
                                              });
                                              LoggerService.debug(
                                                  '🔄 SPINNER: Spinner enabled, starting timeout');
                                              _startSpinnerTimeout();
                                              context
                                                  .read<StreamBloc>()
                                                  .add(StartStream());
                                            }
                                          },
                                    child: SizedBox(
                                      width: isSmall
                                          ? 90.0
                                          : (isTab ? 150.0 : 120.0),
                                      height: isSmall
                                          ? 90.0
                                          : (isTab ? 150.0 : 120.0),
                                      child: Center(
                                        child: (_showLocalLoading ||
                                                _isConnectingState(
                                                    state.playbackState))
                                            ? SizedBox(
                                                width: isSmall
                                                    ? 38.0
                                                    : (isTab ? 64.0 : 50.0),
                                                height: isSmall
                                                    ? 38.0
                                                    : (isTab ? 64.0 : 50.0),
                                                child:
                                                    CircularProgressIndicator(
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(isDark
                                                              ? Colors.white
                                                              : Colors
                                                                  .black87),
                                                  strokeWidth: 4.0,
                                                  strokeCap: StrokeCap.round,
                                                ),
                                              )
                                            : Icon(
                                                _getPlaybackIcon(
                                                    state.playbackState),
                                                size: isSmall
                                                    ? 90.0
                                                    : (isTab ? 150.0 : 120.0),
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Error Display
                            if (state.errorMessage != null) ...[
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Card(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            state.errorMessage!,
                                            style: AppTextStyles.bodyMedium
                                                .copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.refresh),
                                          onPressed: () {
                                            context
                                                .read<StreamBloc>()
                                                .add(RetryStream());
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            // Breathing below the play button before the
                            // floating donate / sleep-timer strip.
                            SizedBox(height: gapBelowButton),
                          ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Bottom-left Donate button
                Positioned(
                  left: _isSmallPhone(context) ? 12 : 16,
                  bottom: _isSmallPhone(context) ? 12 : 16,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      label: 'Donate',
                      button: true,
                      child: RawMaterialButton(
                        onPressed: () => _openDonateSheet(context),
                        elevation: 6,
                        fillColor: const Color(
                            0xFF1E1E1E), // dark gray chip background
                        shape: const CircleBorder(
                          side: BorderSide(
                              color: Color(0x1AFFFFFF),
                              width: 1), // subtle 10% white border
                        ),
                        constraints: BoxConstraints.tightFor(
                          width: _isSmallPhone(context)
                              ? 48
                              : (_isLargeTablet(context) ? 72 : 56),
                          height: _isSmallPhone(context)
                              ? 48
                              : (_isLargeTablet(context) ? 72 : 56),
                        ),
                        child: Icon(
                          Icons.volunteer_activism,
                          color: Colors.white,
                          size: _isSmallPhone(context)
                              ? 20
                              : (_isLargeTablet(context) ? 32 : 24),
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom-right Alarm button (Sleep Timer)
                Positioned(
                  right: _isSmallPhone(context) ? 12 : 16,
                  bottom: _isSmallPhone(context) ? 12 : 16,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      label: 'Sleep timer',
                      button: true,
                      child: RawMaterialButton(
                        onPressed: () => _openAlarmSheet(context),
                        elevation: 6,
                        fillColor: const Color(0xFF1E1E1E),
                        shape: const CircleBorder(
                          side: BorderSide(color: Color(0x1AFFFFFF), width: 1),
                        ),
                        constraints: BoxConstraints.tightFor(
                          width: _isSmallPhone(context)
                              ? 48
                              : (_isLargeTablet(context) ? 72 : 56),
                          height: _isSmallPhone(context)
                              ? 48
                              : (_isLargeTablet(context) ? 72 : 56),
                        ),
                        child: BlocBuilder<SleepTimerCubit, SleepTimerState>(
                          bloc: di.getIt<SleepTimerCubit>(),
                          builder: (context, state) {
                            if (state is SleepTimerRunning ||
                                state is SleepTimerPaused) {
                              final cubit = di.getIt<SleepTimerCubit>();
                              final rem = cubit.remaining;
                              String two(int n) => n.toString().padLeft(2, '0');
                              final m = rem.inMinutes;
                              final s = rem.inSeconds % 60;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.timer,
                                    color: Colors.white,
                                    size: _isSmallPhone(context)
                                        ? 16
                                        : (_isLargeTablet(context) ? 24 : 18),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$m:${two(s)}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: _isSmallPhone(context)
                                          ? 9
                                          : (_isLargeTablet(context) ? 14 : 11),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Icon(
                              Icons.alarm,
                              color: Colors.white,
                              size: _isSmallPhone(context)
                                  ? 20
                                  : (_isLargeTablet(context) ? 32 : 24),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Audio Server Error Modal
                if (state.showServerErrorModal)
                  AudioServerErrorModal(
                    onDismiss: () {
                      context.read<StreamBloc>().add(ClearServerError());
                    },
                    customMessage: state.errorMessage,
                  ),

                // Show Info Modal
                if (_showInfoModal && state.metadata != null)
                  ShowInfoModal(
                    showName: state.metadata!.current.showName,
                    host: state.metadata!.current.host,
                    description: state.metadata!.current.description,
                    onClose: () {
                      setState(() {
                        _showInfoModal = false;
                      });
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openDonateSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return const FractionallySizedBox(
          heightFactor: 0.9,
          child: DonateWebViewSheet(
            initialUrl: 'https://docs.pacifica.org/wbai/donate/',
          ),
        );
      },
    );
  }

  void _openAlarmSheet(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierLabel: 'Sleep Timer',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, a1, a2) => const SleepTimerOverlay(),
      transitionBuilder: (ctx, anim, sec, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }
}
