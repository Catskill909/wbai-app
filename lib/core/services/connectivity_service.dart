import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

/// Simple connectivity + internet access checker
///
/// - Listens to connectivity type changes
/// - Verifies actual internet reachability via a quick HEAD request
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final Dio _dio;

  static const String _probeUrl = 'https://www.google.com/generate_204';
  // A freshly re-enabled radio (e.g. just after Airplane Mode off) needs a
  // moment to actually route traffic. A single short probe gives a false
  // "offline" that latches until the next transport change — which may never
  // come. So the probe is given a slightly longer timeout AND retried.
  static const Duration _timeout = Duration(milliseconds: 3000);
  static const int _probeAttempts = 3;
  static const Duration _probeRetryGap = Duration(milliseconds: 800);

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
      final hasAnyTransport = results.any((r) => r != ConnectivityResult.none);
      if (!hasAnyTransport) return false;
      return await hasInternet();
    } catch (e) {
      return await hasInternet();
    }
  }

  /// Returns true if the device has internet reachability.
  /// Retries a few times so a cold radio doesn't produce a false negative
  /// that latches the app into the offline modal.
  Future<bool> hasInternet() async {
    for (var attempt = 1; attempt <= _probeAttempts; attempt++) {
      if (await _probeOnce()) return true;
      if (attempt < _probeAttempts) {
        await Future.delayed(_probeRetryGap);
      }
    }
    return false;
  }

  /// A single internet reachability probe.
  Future<bool> _probeOnce() async {
    try {
      final res = await _dio.head(
        _probeUrl,
        options: Options(
          validateStatus: (code) => code != null && code >= 200 && code < 400,
        ),
      );
      return res.statusCode == 204 || (res.statusCode ?? 0) >= 200;
    } catch (_) {
      return false;
    }
  }

  /// Emits true/false when connectivity changes and after verifying internet.
  Stream<bool> connectivityStream() async* {
    // Initial value
    final initial = await initialStatus();
    yield initial;

    await for (final results in _connectivity.onConnectivityChanged) {
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
