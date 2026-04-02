import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'logger_service.dart';

/// Handles server health checking for audio streaming endpoints
/// Distinguishes between network connectivity and server availability
class AudioServerHealthChecker {
  static final Dio _dio = Dio();
  static const Duration _healthCheckTimeout = Duration(seconds: 5);
  static const Duration _cacheTimeout = Duration(seconds: 30);

  // Cache to prevent excessive health checks
  static DateTime? _lastHealthCheck;
  static bool? _lastHealthResult;

  static void _configureDio() {
    _dio.options.connectTimeout = _healthCheckTimeout;
    _dio.options.receiveTimeout = _healthCheckTimeout;
    _dio.options.sendTimeout = _healthCheckTimeout;
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 3;
  }

  /// Checks if the audio server is healthy and can serve streams
  /// Returns true if server is available, false if server-specific issues
  /// Throws exception for network connectivity issues
  static Future<AudioServerHealthResult> checkServerHealth(
      String streamUrl) async {
    try {
      // Check cache first to prevent excessive requests
      if (_lastHealthCheck != null && _lastHealthResult != null) {
        final timeSinceLastCheck = DateTime.now().difference(_lastHealthCheck!);
        if (timeSinceLastCheck < _cacheTimeout) {
          LoggerService.info(
              '🏥 AudioServerHealthChecker: Using cached result: $_lastHealthResult');
          return AudioServerHealthResult(
            isHealthy: _lastHealthResult!,
            errorType: _lastHealthResult!
                ? null
                : AudioServerErrorType.serverUnavailable,
            statusCode: _lastHealthResult! ? 200 : null,
          );
        }
      }

      _configureDio();
      LoggerService.info(
          '🏥 AudioServerHealthChecker: Checking server health for: $streamUrl');

      // Use GET request instead of HEAD for Icecast/Shoutcast compatibility
      // Icecast servers return 400 for HEAD requests but 200 for GET
      final response = await _dio.get(
        streamUrl,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.stream, // Don't download the entire stream
          headers: {
            'Range':
                'bytes=0-0', // Request only 1 byte to minimize data transfer
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      LoggerService.info(
          '🏥 AudioServerHealthChecker: Server responded with status: $statusCode');

      // Cache the result
      _lastHealthCheck = DateTime.now();

      // Analyze response
      if (statusCode >= 200 && statusCode < 300) {
        // Server is healthy
        _lastHealthResult = true;
        return AudioServerHealthResult(
          isHealthy: true,
          statusCode: statusCode,
        );
      } else if (statusCode == 404) {
        // Stream not found
        _lastHealthResult = false;
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.streamNotFound,
          statusCode: statusCode,
          message: 'Stream not found on server',
        );
      } else if (statusCode == 503) {
        // Server overloaded
        _lastHealthResult = false;
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.serverOverloaded,
          statusCode: statusCode,
          message: 'Server is temporarily overloaded',
        );
      } else if (statusCode >= 400 && statusCode < 500) {
        // Client error (auth, forbidden, etc.)
        _lastHealthResult = false;
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.authenticationError,
          statusCode: statusCode,
          message: 'Access denied or authentication required',
        );
      } else {
        // Other server error
        _lastHealthResult = false;
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.serverError,
          statusCode: statusCode,
          message: 'Server error occurred',
        );
      }
    } on SocketException catch (e) {
      LoggerService.audioError('🏥 AudioServerHealthChecker: Network error', e);
      // This is a network connectivity issue, not a server issue
      throw NetworkConnectivityException(
          'Network connectivity issue: ${e.message}');
    } on DioException catch (e) {
      LoggerService.audioError('🏥 AudioServerHealthChecker: Dio error', e);

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        // Timeout - could be server or network
        _lastHealthResult = false;
        _lastHealthCheck = DateTime.now();
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.connectionTimeout,
          message: 'Connection to server timed out',
        );
      } else if (e.type == DioExceptionType.connectionError) {
        // Connection refused - server is down
        _lastHealthResult = false;
        _lastHealthCheck = DateTime.now();
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.serverUnavailable,
          message: 'Server is not responding',
        );
      } else {
        // Other Dio errors
        throw NetworkConnectivityException('Network error: ${e.message}');
      }
    } catch (e) {
      LoggerService.audioError(
          '🏥 AudioServerHealthChecker: Unexpected error', e);
      _lastHealthResult = false;
      _lastHealthCheck = DateTime.now();
      return AudioServerHealthResult(
        isHealthy: false,
        errorType: AudioServerErrorType.unknownError,
        message: 'Unexpected error occurred',
      );
    }
  }

  /// Clears the health check cache
  static void clearCache() {
    _lastHealthCheck = null;
    _lastHealthResult = null;
    LoggerService.info('🏥 AudioServerHealthChecker: Cache cleared');
  }

  /// Performs a lightweight ping to check basic connectivity
  static Future<bool> quickPing(String streamUrl) async {
    try {
      _configureDio();
      final response = await _dio.get(
        streamUrl,
        options: Options(
          sendTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
          responseType: ResponseType.stream,
          headers: {
            'Range': 'bytes=0-0',
          },
        ),
      );
      return response.statusCode != null && response.statusCode! < 500;
    } catch (e) {
      return false;
    }
  }
}

/// Result of server health check
class AudioServerHealthResult {
  final bool isHealthy;
  final AudioServerErrorType? errorType;
  final int? statusCode;
  final String? message;

  const AudioServerHealthResult({
    required this.isHealthy,
    this.errorType,
    this.statusCode,
    this.message,
  });

  @override
  String toString() {
    return 'AudioServerHealthResult(isHealthy: $isHealthy, errorType: $errorType, statusCode: $statusCode, message: $message)';
  }
}

/// Types of audio server errors
enum AudioServerErrorType {
  serverUnavailable, // Server is down or not responding
  streamNotFound, // 404 - Stream endpoint not found
  serverOverloaded, // 503 - Server temporarily overloaded
  authenticationError, // 401/403 - Access denied
  connectionTimeout, // Connection or response timeout
  serverError, // 5xx server errors
  unknownError, // Unexpected errors
}

/// Exception for network connectivity issues (not server issues)
class NetworkConnectivityException implements Exception {
  final String message;
  const NetworkConnectivityException(this.message);

  @override
  String toString() => 'NetworkConnectivityException: $message';
}
