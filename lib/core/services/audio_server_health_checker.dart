import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'logger_service.dart';
import '../utils/m3u_parser.dart';

/// Handles server health checking for audio streaming endpoints
/// Distinguishes between network connectivity and server availability
class AudioServerHealthChecker {
  static Dio _dio = Dio();

  /// Test seam: inject a Dio with a mock adapter to exercise server-down paths
  /// without a real network. Pair with [clearCache] between cases.
  static void debugSetDio(Dio dio) => _dio = dio;
  static const Duration _healthCheckTimeout = Duration(seconds: 5);
  // Only successful results are cached, and only briefly. Failures are NEVER
  // cached: a single failed check (e.g. a cold radio after resuming from
  // background) used to poison this static cache for 30s and make every
  // subsequent play return "unhealthy" until the process was killed — the
  // "needs reboot" bug. See play-button-fix.md Phase 1.
  static const Duration _cacheTimeout = Duration(seconds: 5);

  // Cache to prevent excessive health checks (success-only).
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
      // Check cache first to prevent excessive requests.
      // ONLY positive (healthy) results are cached — never failures — so a
      // transient failure can't lock out playback. See play-button-fix.md.
      if (_lastHealthCheck != null && _lastHealthResult == true) {
        final timeSinceLastCheck = DateTime.now().difference(_lastHealthCheck!);
        if (timeSinceLastCheck < _cacheTimeout) {
          LoggerService.info(
              '🏥 AudioServerHealthChecker: Using cached healthy result');
          return const AudioServerHealthResult(
            isHealthy: true,
            statusCode: 200,
          );
        }
      }

      _configureDio();

      // Resolve M3U playlists to the DIRECT Icecast endpoint before probing.
      // WBAI currently streams a direct URL, but the station will switch to a
      // .m3u playlist; this resolves it so we probe the real mount and not just
      // the playlist host. Non-.m3u URLs pass through unchanged.
      //
      // Resolution errors are NOT caught here on purpose — they propagate to
      // the same SocketException/DioException classification below, so a DNS/
      // no-network failure is reported as a network issue while a refused/timed-
      // out playlist host is reported as a server issue. (Both the .m3u fetch
      // and the mount probe are server endpoints, so either failing == down.)
      final String probeUrl = await _resolveDirectStreamUrl(streamUrl);

      LoggerService.info(
          '🏥 AudioServerHealthChecker: Checking server health for: $probeUrl');

      // Use GET request instead of HEAD for Icecast/Shoutcast compatibility
      // Icecast servers return 400 for HEAD requests but 200 for GET
      final response = await _dio.get(
        probeUrl,
        options: Options(
          // Accept EVERY status so the classification below can run. With the
          // old `status < 500` guard, Dio threw on 5xx before we ever looked at
          // the code — which made the 503 and generic-5xx branches below dead
          // code, and routed an overloaded Icecast (503, a very ordinary outage
          // for a radio station) into NetworkConnectivityException. The
          // listener was then told to check their own internet connection while
          // the station was the thing that was down.
          validateStatus: (status) => status != null,
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

      // Analyze response
      if (statusCode >= 200 && statusCode < 300) {
        // Server is healthy — cache ONLY this positive result.
        _lastHealthCheck = DateTime.now();
        _lastHealthResult = true;
        return AudioServerHealthResult(
          isHealthy: true,
          statusCode: statusCode,
        );
      } else if (statusCode == 404) {
        // Stream not found
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.streamNotFound,
          statusCode: statusCode,
          message: 'Stream not found on server',
        );
      } else if (statusCode == 503) {
        // Server overloaded
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.serverOverloaded,
          statusCode: statusCode,
          message: 'Server is temporarily overloaded',
        );
      } else if (statusCode >= 400 && statusCode < 500) {
        // Client error (auth, forbidden, etc.)
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.authenticationError,
          statusCode: statusCode,
          message: 'Access denied or authentication required',
        );
      } else {
        // Other server error
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
        // Timeout - could be server or network. Do NOT cache (transient).
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.connectionTimeout,
          message: 'Connection to server timed out',
        );
      } else if (e.type == DioExceptionType.connectionError) {
        // Connection refused - server is down. Do NOT cache (transient).
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
      // Do NOT cache unexpected failures (transient).
      return AudioServerHealthResult(
        isHealthy: false,
        errorType: AudioServerErrorType.unknownError,
        message: 'Unexpected error occurred',
      );
    }
  }

  /// Resolve an M3U playlist URL to its direct stream endpoint so health
  /// checks probe the actual Icecast server. Non-.m3u URLs are returned as-is.
  /// Throws if the playlist can't be fetched or contains no stream URL — the
  /// caller treats that as "server unavailable".
  static Future<String> _resolveDirectStreamUrl(String url) async {
    if (!url.endsWith('.m3u')) return url;

    LoggerService.info(
        '🏥 AudioServerHealthChecker: Resolving M3U playlist: $url');
    final res = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        // As above: accept everything so a 5xx from the playlist host is
        // reported as the station being down, not as the listener's connection
        // being at fault.
        validateStatus: (status) => status != null,
      ),
    );
    if ((res.statusCode ?? 0) != 200) {
      throw Exception('Playlist returned status ${res.statusCode}');
    }
    final direct = M3UParser.parseStreamUrl(res.data ?? '');
    if (direct == null) {
      throw Exception('No stream URL found in M3U playlist');
    }
    LoggerService.info(
        '🏥 AudioServerHealthChecker: Resolved direct stream: $direct');
    return direct;
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
