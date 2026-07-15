import 'dart:async';
import 'package:dio/dio.dart';
import '../core/services/logger_service.dart';
import '../domain/models/stream_metadata.dart';

class MetadataService {
  static const String _apiUrl =
      'https://confessor2.wbai.org/playlist/_pl_current_ary.php';
  static const Duration _refreshInterval = Duration(seconds: 30);
  // Raised from 5s: the metadata API sometimes responds in 6–8s on a cold start.
  // With a 5s timeout the first fetch FAILED and nothing retried until the 30s
  // periodic timer — so the home screen sat on "Loading stream information…" for
  // up to ~30s. A longer timeout lets a slow-but-working response succeed.
  static const Duration _timeout = Duration(seconds: 12);

  final Dio _dio;
  Timer? _refreshTimer;
  final _metadataController = StreamController<StreamMetadata>.broadcast();
  StreamMetadata? _lastMetadata;

  MetadataService() : _dio = Dio() {
    _dio.options.connectTimeout = _timeout;
    _dio.options.receiveTimeout = _timeout;
    _dio.options.headers = {'Accept': 'application/json'};
    _dio.options.responseType = ResponseType.plain;
    // Retry the FIRST fetch quickly on failure instead of waiting the 30s
    // periodic interval (the cause of the ~30s "Loading stream information…").
    _initialFetchWithRetry();
  }

  /// Cold-start fetch with fast retries. Keeps retrying every few seconds until
  /// the first metadata arrives, so a slow/failed initial response doesn't leave
  /// the UI stuck on the placeholder until the 30s periodic timer fires.
  Future<void> _initialFetchWithRetry() async {
    for (int attempt = 1; attempt <= 6; attempt++) {
      try {
        final metadata = await _fetchFromApi();
        _updateMetadata(metadata);
        return; // success — periodic timer (startFetching) takes over
      } catch (_) {
        if (_lastMetadata != null) {
          _metadataController.add(_lastMetadata!);
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Stream<StreamMetadata> get metadataStream => _metadataController.stream;
  StreamMetadata? get lastMetadata => _lastMetadata;

  void startFetching() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _fetchMetadata());
  }

  void stopFetching() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<StreamMetadata?> fetchMetadataOnce() async {
    try {
      final metadata = await _fetchFromApi();
      _updateMetadata(metadata);
      return metadata;
    } catch (_) {
      return _lastMetadata;
    }
  }

  Future<void> _fetchMetadata() async {
    try {
      final metadata = await _fetchFromApi();
      _updateMetadata(metadata);
    } catch (_) {
      if (_lastMetadata != null) _metadataController.add(_lastMetadata!);
    }
  }

  Future<StreamMetadata> _fetchFromApi() async {
    try {
      final response = await _dio.get(_apiUrl);
      if (response.statusCode == 200) {
        return StreamMetadata.fromJson(response.data as String);
      }
      throw Exception('Status ${response.statusCode}');
    } on DioException catch (e) {
      // Feed not yet live — fail silently
      LoggerService.debug('Metadata feed unavailable (${e.response?.statusCode})');
      rethrow;
    }
  }

  void _updateMetadata(StreamMetadata metadata) {
    _lastMetadata = metadata;
    _metadataController.add(metadata);
  }

  void dispose() {
    stopFetching();
    _metadataController.close();
  }
}
