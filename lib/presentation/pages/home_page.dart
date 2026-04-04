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
import '../../features/news/pages/news_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showLocalLoading = false;
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

  @override
  Widget build(BuildContext context) {
    final isOnline =
        context.select<ConnectivityCubit, bool>((c) => c.state.isOnline);

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
              color: Colors.black,
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
              Icons.radio,
              size: _isLargeTablet(context)
                  ? 48
                  : (_isMediumTablet(context)
                      ? 38
                      : (_isSmallPhone(context) ? 26 : 30)),
              color: Colors.black,
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

            // SPINNER FIX: Only clear spinner when audio actually starts playing or on error
            // Keep spinner during connecting, loading, and buffering states
            if (_showLocalLoading &&
                (state.playbackState == StreamState.playing ||
                    state.playbackState == StreamState.error)) {
              LoggerService.debug(
                  '🔄 SPINNER: Clearing spinner - state is ${state.playbackState}');
              setState(() {
                _showLocalLoading = false;
              });
              _cancelSpinnerTimeout();
            } else if (_showLocalLoading) {
              LoggerService.debug(
                  '🔄 SPINNER: Keeping spinner - state is ${state.playbackState}');
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
                  SemanticsService.sendAnnouncement(View.of(context), 'Playing WBAI stream', dir);
                  break;
                case StreamState.paused:
                  SemanticsService.sendAnnouncement(View.of(context), 'Stream stopped and reset', dir);
                  break;
                case StreamState.loading:
                  SemanticsService.sendAnnouncement(View.of(context), 'Loading audio', dir);
                  break;
                case StreamState.buffering:
                  SemanticsService.sendAnnouncement(View.of(context), 'Buffering audio', dir);
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
              SemanticsService.sendAnnouncement(
                  View.of(context), state.errorMessage!, Directionality.of(context));
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
                      // Preferred image side from screen width — only shrinks when
                      // remaining height after fixed elements is actually smaller.
                      final desiredSide =
                          sw * (isSmall ? 0.80 : (isTab ? 0.70 : 0.85));
                      final bottomPad = isTab ? 100.0 : 80.0;
                      final imgTop = isSmall ? 12.0 : 20.0;
                      final playMarginV =
                          isSmall ? 20.0 : (isTab ? 32.0 : 28.0);
                      final hPad = isSmall ? 12.0 : 16.0;
                      return Padding(
                        padding: EdgeInsets.only(bottom: bottomPad),
                        child: Column(
                          children: [
                            SizedBox(height: imgTop),
                            // Image — Flexible with FlexFit.loose:
                            // uses desiredSide by default; shrinks only when
                            // the remaining column height is genuinely smaller.
                            Flexible(
                              fit: FlexFit.loose,
                              child: Center(
                                child: LayoutBuilder(
                                  builder: (ctx, imgC) {
                                    final side = desiredSide.clamp(
                                        80.0, imgC.maxHeight);
                                    return GestureDetector(
                                      onTap: state.metadata != null
                                          ? () {
                                              setState(() {
                                                _showInfoModal = true;
                                              });
                                            }
                                          : null,
                                      child: Container(
                                        width: side,
                                        height: side,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: const Color(
                                                0x1AFFFFFF), // ~10% white
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
                                                  errorBuilder: (context,
                                                          error,
                                                          stackTrace) =>
                                                      _buildLoadingContainer(
                                                          'Error loading image'),
                                                )
                                              : _buildLoadingContainer(
                                                  'Loading stream information...'),
                                        ),
                                      ),
                                    );
                                  },
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
                                          MediaQuery.of(context).size),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      state.metadata!.current.time,
                                      style: AppTextStyles.showTimeForDevice(
                                          MediaQuery.of(context).size),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (state
                                        .metadata!.current.hasSongInfo) ...[
                                      SizedBox(height: isSmall ? 8 : 10),
                                      Text(
                                        'Song: ${state.metadata!.current.songTitle} - ${state.metadata!.current.songArtist}',
                                        style:
                                            AppTextStyles.bodyLargeForDevice(
                                                MediaQuery.of(context).size),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ] else if (state
                                        .metadata!.next.showName
                                        .isNotEmpty) ...[
                                      SizedBox(height: isSmall ? 8 : 10),
                                      Text(
                                        'Next: ${state.metadata!.next.showName}',
                                        style:
                                            AppTextStyles.bodyMediumForDevice(
                                                MediaQuery.of(context).size),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ] else ...[
                                    const SizedBox(height: 20),
                                    Text(
                                      'Loading stream information...',
                                      style: AppTextStyles.bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Playback Control with Loading State
                            Container(
                              alignment: Alignment.center,
                              margin: EdgeInsets.symmetric(
                                  vertical: playMarginV),
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
                                  color: Colors.white,
                                  shape: const CircleBorder(
                                    side: BorderSide(
                                        color: Colors.black87, width: 2),
                                  ),
                                  elevation: 4,
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
                                        child: _showLocalLoading
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
                                                              Color>(
                                                          Colors.black87),
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
                                                color: Colors.black87,
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
                          ],
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

                // Bottom-center News button
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(bottom: 8),
                    child: Center(
                      child: Semantics(
                        label: 'News',
                        button: true,
                        child: RawMaterialButton(
                          onPressed: () => Navigator.push(
                            context,
                            PageRouteBuilder(
                              transitionDuration:
                                  const Duration(milliseconds: 380),
                              reverseTransitionDuration:
                                  const Duration(milliseconds: 300),
                              pageBuilder: (_, __, ___) => const NewsPage(),
                              transitionsBuilder:
                                  (_, animation, __, child) {
                                final tween = Tween(
                                  begin: const Offset(0, 1),
                                  end: Offset.zero,
                                ).chain(CurveTween(curve: Curves.easeOutCubic));
                                return SlideTransition(
                                  position: animation.drive(tween),
                                  child: child,
                                );
                              },
                            ),
                          ),
                          elevation: 6,
                          fillColor: const Color(0xFF565A60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          constraints: BoxConstraints.tightFor(
                            width: _isSmallPhone(context)
                                ? 96
                                : (_isLargeTablet(context) ? 140 : 112),
                            height: _isSmallPhone(context)
                                ? 38
                                : (_isLargeTablet(context) ? 52 : 44),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.article_outlined,
                                color: Colors.white,
                                size: _isSmallPhone(context)
                                    ? 16
                                    : (_isLargeTablet(context) ? 24 : 18),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'NEWS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: _isSmallPhone(context)
                                      ? 12
                                      : (_isLargeTablet(context) ? 18 : 14),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
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
