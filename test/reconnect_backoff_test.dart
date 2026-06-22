import 'package:flutter_test/flutter_test.dart';
import 'package:wbai_radio/services/audio_service/wbai_audio_handler.dart';

void main() {
  group('WBAIAudioHandler.reconnectBackoff', () {
    test('grows exponentially: 2s, 4s, 8s, 16s', () {
      expect(WBAIAudioHandler.reconnectBackoff(1), const Duration(seconds: 2));
      expect(WBAIAudioHandler.reconnectBackoff(2), const Duration(seconds: 4));
      expect(WBAIAudioHandler.reconnectBackoff(3), const Duration(seconds: 8));
      expect(WBAIAudioHandler.reconnectBackoff(4), const Duration(seconds: 16));
    });

    test('caps at 30s', () {
      expect(WBAIAudioHandler.reconnectBackoff(5), const Duration(seconds: 30));
      expect(WBAIAudioHandler.reconnectBackoff(10), const Duration(seconds: 30));
    });

    test('never returns less than 2s', () {
      expect(WBAIAudioHandler.reconnectBackoff(0), const Duration(seconds: 2));
    });
  });
}
