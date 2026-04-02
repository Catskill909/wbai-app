import 'dart:io';
import '../services/audio_server_health_checker.dart';
import '../services/logger_service.dart';
import '../constants/stream_constants.dart';

/// Testing utilities for audio server error scenarios
/// This class provides methods to simulate various server failure conditions
/// for testing the audio error handling system without needing to control the actual Icecast server
class AudioServerTestingStrategy {
  static bool _isTestMode = false;
  static AudioServerErrorType? _forcedErrorType;
  static int? _forcedStatusCode;

  /// Enable test mode to simulate server errors
  static void enableTestMode() {
    _isTestMode = true;
    LoggerService.info('🧪 AudioServerTestingStrategy: Test mode ENABLED');
  }

  /// Disable test mode to use real server health checks
  static void disableTestMode() {
    _isTestMode = false;
    _forcedErrorType = null;
    _forcedStatusCode = null;
    LoggerService.info('🧪 AudioServerTestingStrategy: Test mode DISABLED');
  }

  /// Force a specific server error type for testing
  static void forceServerError(AudioServerErrorType errorType, {int? statusCode}) {
    _forcedErrorType = errorType;
    _forcedStatusCode = statusCode;
    LoggerService.info('🧪 AudioServerTestingStrategy: Forcing error type: $errorType (status: $statusCode)');
  }

  /// Simulate server being completely down (connection refused)
  static void simulateServerDown() {
    forceServerError(AudioServerErrorType.serverUnavailable);
  }

  /// Simulate stream not found (404 error)
  static void simulateStreamNotFound() {
    forceServerError(AudioServerErrorType.streamNotFound, statusCode: 404);
  }

  /// Simulate server overloaded (503 error)
  static void simulateServerOverloaded() {
    forceServerError(AudioServerErrorType.serverOverloaded, statusCode: 503);
  }

  /// Simulate connection timeout
  static void simulateConnectionTimeout() {
    forceServerError(AudioServerErrorType.connectionTimeout);
  }

  /// Simulate authentication error (401/403)
  static void simulateAuthError() {
    forceServerError(AudioServerErrorType.authenticationError, statusCode: 401);
  }

  /// Clear any forced errors (return to normal operation)
  static void clearForcedErrors() {
    _forcedErrorType = null;
    _forcedStatusCode = null;
    LoggerService.info('🧪 AudioServerTestingStrategy: Cleared forced errors');
  }

  /// Check if we're in test mode and should return a forced error
  static AudioServerHealthResult? getTestResult() {
    if (!_isTestMode || _forcedErrorType == null) {
      return null;
    }

    LoggerService.info('🧪 AudioServerTestingStrategy: Returning test result: $_forcedErrorType');

    switch (_forcedErrorType!) {
      case AudioServerErrorType.serverUnavailable:
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.serverUnavailable,
          message: 'Test: Server is unavailable',
        );
      case AudioServerErrorType.streamNotFound:
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.streamNotFound,
          statusCode: _forcedStatusCode ?? 404,
          message: 'Test: Stream not found',
        );
      case AudioServerErrorType.serverOverloaded:
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.serverOverloaded,
          statusCode: _forcedStatusCode ?? 503,
          message: 'Test: Server is overloaded',
        );
      case AudioServerErrorType.connectionTimeout:
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.connectionTimeout,
          message: 'Test: Connection timed out',
        );
      case AudioServerErrorType.authenticationError:
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.authenticationError,
          statusCode: _forcedStatusCode ?? 401,
          message: 'Test: Authentication failed',
        );
      case AudioServerErrorType.serverError:
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.serverError,
          statusCode: _forcedStatusCode ?? 500,
          message: 'Test: Server error',
        );
      case AudioServerErrorType.unknownError:
        return AudioServerHealthResult(
          isHealthy: false,
          errorType: AudioServerErrorType.unknownError,
          message: 'Test: Unknown error',
        );
    }
  }

  /// Test the actual server health (bypasses test mode)
  static Future<AudioServerHealthResult> testRealServerHealth() async {
    final wasTestMode = _isTestMode;
    _isTestMode = false;
    
    try {
      final result = await AudioServerHealthChecker.checkServerHealth(
        StreamConstants.streamUrl
      );
      LoggerService.info('🧪 Real server health check result: $result');
      return result;
    } finally {
      _isTestMode = wasTestMode;
    }
  }

  /// Create a mock HTTP server for testing (advanced testing)
  static Future<HttpServer> createMockServer({
    int port = 8888,
    int responseCode = 200,
    String responseBody = 'OK',
    Duration? delay,
  }) async {
    final server = await HttpServer.bind('localhost', port);
    
    server.listen((HttpRequest request) async {
      if (delay != null) {
        await Future.delayed(delay);
      }
      
      request.response.statusCode = responseCode;
      request.response.write(responseBody);
      await request.response.close();
    });
    
    LoggerService.info('🧪 Mock server started on localhost:$port (status: $responseCode)');
    return server;
  }

  /// Test scenarios for manual testing
  static void printTestingScenarios() {
    LoggerService.info('''
🧪 AUDIO SERVER ERROR TESTING SCENARIOS:

1. SERVER DOWN TEST:
   - Call: AudioServerTestingStrategy.simulateServerDown()
   - Expected: AudioServerErrorModal appears with "server unavailable" message
   - Expected: Play button resets to initial state
   - Expected: Lockscreen controls are cleared

2. STREAM NOT FOUND TEST:
   - Call: AudioServerTestingStrategy.simulateStreamNotFound()
   - Expected: AudioServerErrorModal appears with "stream not found" message
   - Expected: Play button resets to initial state

3. SERVER OVERLOADED TEST:
   - Call: AudioServerTestingStrategy.simulateServerOverloaded()
   - Expected: AudioServerErrorModal appears with "server overloaded" message
   - Expected: Play button resets to initial state

4. CONNECTION TIMEOUT TEST:
   - Call: AudioServerTestingStrategy.simulateConnectionTimeout()
   - Expected: AudioServerErrorModal appears with "connection timeout" message
   - Expected: Play button resets to initial state

5. AUTHENTICATION ERROR TEST:
   - Call: AudioServerTestingStrategy.simulateAuthError()
   - Expected: AudioServerErrorModal appears with "access denied" message
   - Expected: Play button resets to initial state

6. RECOVERY TEST:
   - After any error scenario, call: AudioServerTestingStrategy.clearForcedErrors()
   - Tap "OK" on error modal
   - Try playing again
   - Expected: Normal playback should work

7. NETWORK VS SERVER ERROR TEST:
   - Turn off WiFi/cellular (network error) - should show NetworkLostAlert
   - Turn on WiFi/cellular, then call simulateServerDown() - should show AudioServerErrorModal
   - Verify different modals appear for different error types

USAGE IN DEBUG MODE:
- Add these calls to a debug menu or use Flutter Inspector
- Test each scenario and verify UI behavior
- Check logs for proper error classification
- Verify lockscreen controls are reset properly

AUTOMATED TESTING:
- Use widget tests with these simulation methods
- Test BLoC state changes
- Verify modal appearance and dismissal
- Test play button state transitions
    ''');
  }
}

/// Extension to AudioServerHealthChecker for testing integration
extension AudioServerHealthCheckerTesting on AudioServerHealthChecker {
  /// Modified health check that respects test mode
  static Future<AudioServerHealthResult> checkServerHealthWithTesting(String streamUrl) async {
    // Check if we should return a test result
    final testResult = AudioServerTestingStrategy.getTestResult();
    if (testResult != null) {
      return testResult;
    }
    
    // Otherwise, perform real health check
    return AudioServerHealthChecker.checkServerHealth(streamUrl);
  }
}
