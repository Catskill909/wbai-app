import 'package:flutter/services.dart';
import '../../core/services/logger_service.dart';

class LockscreenService {
  static const _platform = MethodChannel('com.wpfwapp.radio/metadata');
  
  Future<void> initializeAudio() async {
    try {
      await _platform.invokeMethod('initializeAudio');
    } catch (e) {
      LoggerService.error('Failed to initialize audio: $e');
    }
  }

  Future<void> updateMetadata({
    required String title,
    required String artist,
  }) async {
    try {
      await _platform.invokeMethod('updateMetadata', {
        'title': title,
        'artist': artist,
      });
    } catch (e) {
      LoggerService.error('Failed to update metadata: $e');
    }
  }
}
