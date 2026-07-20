import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:io';
import 'core/di/service_locator.dart';
import 'core/constants/stream_constants.dart';
import 'core/services/logger_service.dart';
import 'core/services/audio_server_health_checker.dart';
import 'data/repositories/stream_repository.dart';
// import 'presentation/bloc/stream_bloc.dart'; // Removed: Using factory function instead
import 'presentation/pages/home_page.dart';
import 'presentation/theme/app_theme.dart';
import 'services/metadata_service_native.dart';
import 'services/audio_service/wbai_audio_handler.dart';
import 'services/samsung_media_session_service.dart';
import 'presentation/bloc/connectivity_cubit.dart';
import 'presentation/bloc/theme_cubit.dart';
import 'presentation/widgets/network_lost_alert.dart';

// Global navigator key (kept if needed later)
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Preserve splash screen while initializing
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Light status bar icons by default (app now opens in dark mode by
  // default). The AppBar's theme-specific systemOverlayStyle takes over
  // once the first frame renders and flips this per the user's choice.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  // Lock orientation to portrait on all devices (phone and tablet).
  // portraitUp only, to match the iOS Info.plist (no upside-down).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  LoggerService.info('🔒 Orientation locked to portrait (phone + tablet)');

  // Initialize logger
  LoggerService.init();
  LoggerService.info('Starting WBAI Radio app');

  try {
    // Setup dependency injection FIRST (preserves existing pattern - CRITICAL CONSTRAINT)
    await setupServiceLocator();

    // CRITICAL: Initialize AudioService for Android notifications (from working Pacifica app)
    // This is the missing piece that makes Samsung J7 lockscreen controls work
    await AudioService.init(
      builder: () => getIt<WBAIAudioHandler>(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.wbaifm.radio.audio',
        androidNotificationChannelName: 'WBAI Radio',
        // Must be false to pair with androidStopForegroundOnPause: false
        // (audio_service asserts an ongoing notification requires stop-on-pause).
        androidNotificationOngoing: false,
        // APP-CLOSE NOTIFICATION FIX (ported from KPFK, proven by native logcat):
        // with `true`, pause drops the service out of the foreground; swiping the
        // app away then kills it before onTaskRemoved can run stop(), orphaning the
        // notification (close-while-paused). `false` keeps the service foreground
        // through pause so onTaskRemoved fires reliably in both states. Safe for the
        // lock screen — the art blank was a separate STATE_NONE issue fixed in
        // _broadcastState, not this flag.
        androidStopForegroundOnPause: false,
        androidNotificationChannelDescription: 'WBAI Radio Audio Playback',
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: false,
        androidNotificationClickStartsActivity: true,
      ),
    );
    // === iOS REMOTE COMMAND HANDLER INIT (PRODUCTION - DO NOT MODIFY) ===
    // Set up remote lockscreen command handler for iOS
    if (Platform.isIOS) {
      try {
        final audioHandler = getIt<WBAIAudioHandler>();
        NativeMetadataService.audioHandler = audioHandler;
      } catch (e) {
        LoggerService.error('Failed to register iOS remote command handler: $e');
      }
    }
    // === END iOS REMOTE COMMAND HANDLER INIT (UNTOUCHED) ===

    // ANDROID-ONLY: register app close observer (detached only)
    if (Platform.isAndroid) {
      // Initialize Samsung MediaSession channel so native callbacks (onAppClosing, media actions)
      // can be received by Dart side.
      try {
        await SamsungMediaSessionService.initialize();
        LoggerService.info(
            '🤖 SAMSUNG: MediaSession service initialized in main()');
      } catch (e) {
        LoggerService.error(
            '🤖 SAMSUNG: Failed to initialize Samsung service in main(): $e');
      }
      WidgetsBinding.instance.addObserver(_AndroidAppCloseObserver());
      LoggerService.info(
          '🤖 Android app-close observer registered (detached only)');
    }

    // ALL PLATFORMS: re-check connectivity + clear the health-check cache when
    // the app returns to the foreground. Without this, a cold-radio probe that
    // failed while backgrounded could leave isOnline latched false (dead play
    // button) until a transport change. See play-button-fix.md Phase 1 + 3.
    WidgetsBinding.instance.addObserver(_AppResumeObserver());
    LoggerService.info('🔄 App-resume observer registered (all platforms)');

    // Remove splash after minimum display time, but don't block runApp
    Future.delayed(const Duration(seconds: 2), FlutterNativeSplash.remove);

    runApp(const WBAIRadioApp());
  } catch (e, stackTrace) {
    LoggerService.error('Error initializing app', e, stackTrace);
    FlutterNativeSplash.remove();
    rethrow;
  }
}

// ANDROID-ONLY: Lifecycle observer that reacts ONLY when the app is truly closing
// (AppLifecycleState.detached). It does NOT run on background/paused.
class _AndroidAppCloseObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.detached) {
      try {
        if (!Platform.isAndroid) return;

        final handler = getIt<WBAIAudioHandler>();
        final wasPlaying = handler.playbackState.value.playing;

        // Dispose/clear on app close to remove tray and release resources.
        await getIt<StreamRepository>()
            .stopAndColdReset(preserveMetadata: false);

        LoggerService.info(
          '🤖 Android app closed (detached). Cleaned up. wasPlaying=$wasPlaying',
        );
      } catch (e) {
        LoggerService.error('App close cleanup failed', e);
      }
    }
  }
}

// ALL PLATFORMS: reacts when the app returns to the foreground.
// Clears the (success-only) health-check cache so the next play re-probes the
// server, and re-checks connectivity so a stale offline reading from a cold
// radio doesn't leave the play button disabled.
class _AppResumeObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      LoggerService.info('🔄 App resumed - clearing health cache, re-checking connectivity');
      AudioServerHealthChecker.clearCache();
      try {
        getIt<ConnectivityCubit>().checkNow();
      } catch (e) {
        LoggerService.error('🔄 App-resume connectivity check failed', e);
      }
    }
  }
}

class WBAIRadioApp extends StatelessWidget {
  const WBAIRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => createStreamBloc()),
        BlocProvider(create: (_) => getIt<ConnectivityCubit>()..initialize()),
        BlocProvider(create: (_) => getIt<ThemeCubit>()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) => MaterialApp(
          title: StreamConstants.stationName,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          home: const HomePage(),
          builder: (context, child) {
            final connState = context.watch<ConnectivityCubit>().state;
            // Kick an explicit first check on first frame
            if (connState.firstRun) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.read<ConnectivityCubit>().checkNow();
                }
              });
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                child ?? const SizedBox.shrink(),
                if (!connState.isOnline) const NetworkLostAlert(),
              ],
            );
          },
        ),
      ),
    );
  }
}

