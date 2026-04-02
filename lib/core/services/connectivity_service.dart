import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'logger_service.dart';

/// Simple connectivity + internet access checker
///
/// - Listens to connectivity type changes
/// - Verifies actual internet reachability via a quick HEAD request
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final Dio _dio;

  static const String _probeUrl = 'https://www.google.com/generate_204';
  static const Duration _timeout = Duration(milliseconds: 1500);

  ConnectivityService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = _timeout;
    _dio.options.receiveTimeout = _timeout;
    _dio.options.sendTimeout = _timeout;
  }

  /// Fast initial status: if there is no transport (Airplane Mode), return false immediately.
  /// Otherwise, verify with an internet probe.
  Future<bool> initialStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      LoggerService.info('[Connectivity] checkConnectivity initial=$results');
      // If no transports are available, immediately offline
      final hasAnyTransport = results.any((r) => r != ConnectivityResult.none);
      if (!hasAnyTransport) return false;
      return await hasInternet();
    } catch (e) {
      LoggerService.info('[Connectivity] initialStatus error=$e');
      return await hasInternet();
    }
  }

  /// Returns true if the device has internet reachability.
  Future<bool> hasInternet() async {
    try {
      LoggerService.debug('[Connectivity] Probing internet...');
      final res = await _dio.head(
        _probeUrl,
        options: Options(
          validateStatus: (code) => code != null && code >= 200 && code < 400,
        ),
      );
      // Accept 204/200/3xx as reachable
      final ok = res.statusCode == 204 || (res.statusCode ?? 0) >= 200;
      LoggerService.info('[Connectivity] Probe result code=${res.statusCode} => online=$ok');
      return ok;
    } catch (_) {
      LoggerService.info('[Connectivity] Probe failed => offline');
      return false;
    }
  }

  /// Emits true/false when connectivity changes and after verifying internet.
  Stream<bool> connectivityStream() async* {
    // Initial value
    final initial = await initialStatus();
    LoggerService.info('[Connectivity] Initial internet=$initial');
    yield initial;

    await for (final results in _connectivity.onConnectivityChanged) {
      LoggerService.debug('[Connectivity] Connectivity changed: $results');
      final hasAnyTransport = results.any((r) => r != ConnectivityResult.none);
      if (!hasAnyTransport) {
        // No radios active (e.g., Airplane Mode)
        yield false;
      } else {
        final online = await hasInternet();
        yield online;
      }
    }
  }
}
