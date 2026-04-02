import 'dart:async';
import '../domain/models/stream_metadata.dart';

class MetadataService {
  final _metadataController = StreamController<StreamMetadata>.broadcast();
  StreamMetadata? _lastMetadata;

  // Metadata feed disabled until WBAI feed URL is confirmed
  MetadataService();

  Stream<StreamMetadata> get metadataStream => _metadataController.stream;
  StreamMetadata? get lastMetadata => _lastMetadata;

  void startFetching() {}
  void stopFetching() {}

  Future<StreamMetadata?> fetchMetadataOnce() async => _lastMetadata;

  void dispose() {
    _metadataController.close();
  }
}
