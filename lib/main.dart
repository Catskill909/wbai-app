import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:io';
import 'core/di/service_locator.dart';
import 'core/constants/stream_constants.dart';
import 'core/services/logger_service.dart';
import 'data/repositories/stream_repository.dart';
// import 'presentation/bloc/stream_bloc.dart'; // Removed: Using factory function instead
import 'presentation/pages/home_page.dart';
import 'presentation/theme/app_theme.dart';
import 'services/metadata_service_native.dart';
import 'services/audio_service/wbai_audio_handler.dart';
import 'services/samsung_media_session_service.dart';
import 'presentation/bloc/connectivity_cubit.dart';
import 'presentation/widgets/network_lost_alert.dart';

// Global navigator key (kept if needed later)
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Preserve splash screen while initializing
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Force dark status bar icons for light/white background
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  // ANDROID-ONLY: Lock orientation to portrait mode
  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    LoggerService.info('🤖 ANDROID: Orientation locked to portrait mode');
  }

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
        androidNotificationOngoing: true,
        androidStopForegroundOnPause:
            true, // ROLLBACK: Restore original working value
        androidNotificationChannelDescription: 'WBAI Radio Audio Playback',
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: false,
        androidNotificationClickStartsActivity: true,
      ),
    );
    LoggerService.info(
        '🎯 SAMSUNG FIX: AudioService.init() completed with androidStopForegroundOnPause=true');

    // === iOS REMOTE COMMAND HANDLER INIT (PRODUCTION - DO NOT MODIFY) ===
    // Set up remote lockscreen command handler for iOS
    if (Platform.isIOS) {
      try {
        final audioHandler = getIt<WBAIAudioHandler>();
        NativeMetadataService.audioHandler = audioHandler;
        LoggerService.info('🔒 Registered iOS remote command handler');
      } catch (e) {
        LoggerService.error(
            '🔒 Failed to register iOS remote command handler: $e');
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

class WBAIRadioApp extends StatelessWidget {
  const WBAIRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => createStreamBloc()),
        BlocProvider(create: (_) => getIt<ConnectivityCubit>()..initialize()),
      ],
      child: MaterialApp(
        title: StreamConstants.stationName,
        theme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
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
    );
  }
}

