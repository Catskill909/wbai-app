import 'dart:async';
import 'package:dio/dio.dart';
import '../core/services/logger_service.dart';
import '../domain/models/stream_metadata.dart';

class MetadataService {
  static const String _apiUrl =
      'https://www.kpfk.org/playlist/_pl_current_ary.php';
  static const Duration _refreshInterval =
      Duration(seconds: 15); // More frequent updates
  static const Duration _timeout = Duration(seconds: 5);

  final Dio _dio;
  Timer? _refreshTimer;
  final _metadataController = StreamController<StreamMetadata>.broadcast();
  StreamMetadata? _lastMetadata;

  MetadataService() : _dio = Dio() {
    LoggerService.info(
        '🎵 MetadataService: Initializing with simplified fetch strategy');
    _dio.options.connectTimeout = _timeout;
    _dio.options.receiveTimeout = _timeout;
    _dio.options.headers = {
      'Accept': 'application/json',
    };
    _dio.options.responseType = ResponseType.plain; // Get raw response

    // CRITICAL FIX: Single initial fetch, no aggressive retries or duplicates
    LoggerService.info('🎵 MetadataService: Starting initial fetch');
    _fetchMetadata();
  }

  /// Stream of metadata updates
  Stream<StreamMetadata> get metadataStream => _metadataController.stream;

  /// Last successfully fetched metadata
  StreamMetadata? get lastMetadata => _lastMetadata;

  /// Start fetching metadata periodically
  void startFetching() {
    // Start periodic updates
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _fetchMetadata());
  }

  /// Stop fetching metadata
  void stopFetching() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Fetch metadata once manually
  Future<StreamMetadata?> fetchMetadataOnce() async {
    LoggerService.info('🎵 MetadataService: Manual metadata fetch requested');
    try {
      final metadata = await _fetchFromApi();
      LoggerService.info(
          '🎵 MetadataService: Manual fetch SUCCESS - Show: ${metadata.current.showName}');
      _updateMetadata(metadata);
      return metadata;
    } catch (e) {
      LoggerService.debug('🎵 MetadataService: Manual fetch failed: $e');
      return _lastMetadata;
    }
  }

  Future<void> _fetchMetadata() async {
    try {
      final metadata = await _fetchFromApi();
      LoggerService.info(
          '🎵 Periodic fetch SUCCESS: Show="${metadata.current.showName}", Host="${metadata.current.host}"');
      _updateMetadata(metadata);
    } catch (e) {
      LoggerService.debug('Metadata fetch failed: $e');
      if (_lastMetadata != null) {
        _metadataController.add(_lastMetadata!);
      }
    }
  }

  Future<StreamMetadata> _fetchFromApi() async {
    LoggerService.debug('Fetching from API: $_apiUrl');
    try {
      final response = await _dio.get(_apiUrl);
      if (response.statusCode == 200) {
        final data = response.data as String;
        return StreamMetadata.fromJson(data);
      }
      throw Exception('Metadata fetch returned ${response.statusCode}');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      LoggerService.debug('Metadata fetch failed (status=$status) — feed unavailable');
      throw Exception('Metadata unavailable (status=$status)');
    } catch (e) {
      LoggerService.debug('Metadata fetch error: $e');
      rethrow;
    }
  }

  void _updateMetadata(StreamMetadata metadata) {
    LoggerService.info('🎵 MetadataService: Pushing metadata update to stream');
    LoggerService.info(
        '🎵 SHOW: "${metadata.current.showName}", HOST: "${metadata.current.host}"');
    if (metadata.current.hasSongInfo) {
      LoggerService.info(
          '🎵 SONG: "${metadata.current.songTitle}", ARTIST: "${metadata.current.songArtist}"');
    }

    _lastMetadata = metadata;
    _metadataController.add(metadata);
  }

  void dispose() {
    stopFetching();
    _metadataController.close();
  }
}
