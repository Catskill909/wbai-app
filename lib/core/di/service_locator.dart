// import 'package:get_it/get_it.dart';  // REMOVED: Conflicts with AudioService
import '../../data/repositories/stream_repository.dart';
import '../../services/audio_service/wbai_audio_handler.dart';
import '../../services/metadata_service.dart';
import '../../presentation/bloc/stream_bloc.dart';
import '../services/connectivity_service.dart';
import '../services/audio_state_manager.dart';
import '../../presentation/bloc/connectivity_cubit.dart';
import '../../presentation/bloc/sleep_timer_cubit.dart';
import '../../features/news/repository/news_repository.dart';
import '../../features/news/bloc/news_cubit.dart';

// Simple service registry without get_it dependency
class ServiceRegistry {
  static WBAIAudioHandler? _audioHandler;
  static MetadataService? _metadataService;
  static StreamRepository? _streamRepository;
  static AudioStateManager? _audioStateManager;
  static ConnectivityService? _connectivityService;
  static ConnectivityCubit? _connectivityCubit;
  static SleepTimerCubit? _sleepTimerCubit;
  static NewsRepository? _newsRepository;
  static NewsCubit? _newsCubit;

  static T get<T>() {
    if (T == WBAIAudioHandler) return _audioHandler as T;
    if (T == MetadataService) return _metadataService as T;
    if (T == StreamRepository) return _streamRepository as T;
    if (T == AudioStateManager) return _audioStateManager as T;
    if (T == ConnectivityService) return _connectivityService as T;
    if (T == ConnectivityCubit) return _connectivityCubit as T;
    if (T == SleepTimerCubit) return _sleepTimerCubit as T;
    if (T == NewsRepository) return _newsRepository as T;
    if (T == NewsCubit) return _newsCubit as T;
    throw Exception('Service not registered: $T');
  }
}

// Keep exact same initialization pattern to avoid breaking app
Future<void> setupServiceLocator() async {
  // Services - Register in same order to avoid breaking app
  ServiceRegistry._audioStateManager = AudioStateManager();
  
  // CRITICAL: Keep exact same audio handler initialization
  final audioHandler = await WBAIAudioHandler.create();
  ServiceRegistry._audioHandler = audioHandler;

  ServiceRegistry._metadataService = MetadataService();
  ServiceRegistry._connectivityService = ConnectivityService();

  // Repository
  ServiceRegistry._streamRepository = StreamRepository(
    audioHandler: ServiceRegistry.get<WBAIAudioHandler>(),
    metadataService: ServiceRegistry.get<MetadataService>(),
  );

  // PHASE 1: Wire up AudioStateManager to listen to StreamRepository
  ServiceRegistry.get<AudioStateManager>().startListeningToStreamRepository(
    ServiceRegistry.get<StreamRepository>()
  );

  // Register ConnectivityCubit
  ServiceRegistry._connectivityCubit = ConnectivityCubit(
    service: ServiceRegistry.get<ConnectivityService>(),
    streamRepository: ServiceRegistry.get<StreamRepository>(),
  );

  // Sleep Timer Cubit as a singleton
  ServiceRegistry._sleepTimerCubit = SleepTimerCubit(
    ServiceRegistry.get<StreamRepository>()
  );

  // News feature — lazy singleton (fetch only triggered when NewsPage opens)
  ServiceRegistry._newsRepository = NewsRepository();
  ServiceRegistry._newsCubit = NewsCubit(ServiceRegistry.get<NewsRepository>());
}

// Backward compatibility
T getIt<T>() => ServiceRegistry.get<T>();

// Factory method for StreamBloc (since it's not a singleton)
StreamBloc createStreamBloc() => StreamBloc(
  repository: ServiceRegistry.get<StreamRepository>(),
);
