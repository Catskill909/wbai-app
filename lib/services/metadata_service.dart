import 'dart:async';
import 'package:dio/dio.dart';
import '../core/services/logger_service.dart';
import '../domain/models/stream_metadata.dart';

class MetadataService {
  static const String _apiUrl =
      'https://www.kpfk.org/playlist/_pl_current_ary.php';
  static const Duration _refreshInterval = Duration(seconds: 30);
  static const Duration _timeout = Duration(seconds: 5);

  final Dio _dio;
  Timer? _refreshTimer;
  final _metadataController = StreamController<StreamMetadata>.broadcast();
  StreamMetadata? _lastMetadata;

  MetadataService() : _dio = Dio() {
    _dio.options.connectTimeout = _timeout;
    _dio.options.receiveTimeout = _timeout;
    _dio.options.headers = {'Accept': 'application/json'};
    _dio.options.responseType = ResponseType.plain;
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
    LoggerService.info('Metadata: Show="${metadata.current.showName}"');
    _lastMetadata = metadata;
    _metadataController.add(metadata);
  }

  void dispose() {
    stopFetching();
    _metadataController.close();
  }
}
