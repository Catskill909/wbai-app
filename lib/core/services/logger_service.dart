import 'package:logging/logging.dart';

class LoggerService {
  static final Logger _logger = Logger('WBAIRadio');
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;

    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      // In development, print to console
      // In production, this could be integrated with a crash reporting service
      final message = '${record.level.name}: ${record.time}: '
          '${record.loggerName}: ${record.message}';

      if (record.error != null) {
        // ignore: avoid_print
        print('  error: ${record.error}');
      }

      // Add your preferred logging destination here
      // For now, we'll use print in a more structured way
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
