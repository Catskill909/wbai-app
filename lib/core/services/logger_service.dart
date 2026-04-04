import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class LoggerService {
  static final Logger _logger = Logger('WBAIRadio');
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;

    // Only show INFO+ in debug builds; suppress to WARNING in release/profile.
    Logger.root.level = kDebugMode ? Level.INFO : Level.WARNING;
    Logger.root.onRecord.listen((record) {
      final message = '${record.level.name}: ${record.time}: '
          '${record.loggerName}: ${record.message}';

      if (record.error != null) {
        // ignore: avoid_print
        print('  error: ${record.error}');
      }

      // ignore: avoid_print
      print(message);
    });

    _initialized = true;
  }

  static void info(String message) {
    _logger.info(message);
  }

  static void warning(String message) {
    _logger.warning(message);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }

  static void debug(String message) {
    _logger.fine(message);
  }

  static void audioError(String message,
      [Object? error, StackTrace? stackTrace]) {
    _logger.severe('AudioService: $message', error, stackTrace);
  }

  static void webViewError(String message,
      [Object? error, StackTrace? stackTrace]) {
    _logger.severe('WebView: $message', error, stackTrace);
  }

  static void metadataError(String message,
      [Object? error, StackTrace? stackTrace]) {
    _logger.severe('Metadata: $message', error, stackTrace);
  }

  static void streamError(String message,
      [Object? error, StackTrace? stackTrace]) {
    _logger.severe('Stream: $message', error, stackTrace);
  }
}
