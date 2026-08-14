import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wbai_radio/core/services/audio_server_health_checker.dart';

/// Minimal Dio adapter that returns canned responses (or throws) based on the
/// requested URL, so we can simulate "M3U host down" vs "Icecast mount down"
/// without a real network. WBAI currently streams a direct URL but will switch
/// to a .m3u playlist; the checker resolves .m3u to a direct mount and probes
/// THAT, so both cases are covered here.
class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) onFetch;
  _FakeAdapter(this.onFetch);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      onFetch(options);

  @override
  void close({bool force = false}) {}
}

const _m3uUrl = 'https://docs.example.org/wbai.m3u';
const _directUrl = 'https://streaming.wbai.org/wbai_verizon';
const _mountUrl = 'http://fake-icecast.test/wbai_128';
const _m3uBody = '#EXTM3U\n$_mountUrl\n';

ResponseBody _ok(String body, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(body, 200,
        headers: headers ?? {Headers.contentTypeHeader: ['text/plain']});

DioException _connectionRefused(RequestOptions o) =>
    DioException(requestOptions: o, type: DioExceptionType.connectionError);

void _installAdapter(ResponseBody Function(RequestOptions) handler) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter(handler);
  AudioServerHealthChecker.debugSetDio(dio);
}

void main() {
  setUp(AudioServerHealthChecker.clearCache);
  tearDown(AudioServerHealthChecker.clearCache);

  test('healthy: direct URL mount returns 200 (current WBAI setup)', () async {
    _installAdapter((o) => _ok('')); // mount probe OK
    final result = await AudioServerHealthChecker.checkServerHealth(_directUrl);
    expect(result.isHealthy, isTrue);
  });

  test('healthy: M3U resolves and the Icecast mount returns 200', () async {
    _installAdapter((o) {
      if (o.uri.toString().endsWith('.m3u')) return _ok(_m3uBody);
      return _ok(''); // mount probe OK
    });
    final result = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(result.isHealthy, isTrue);
  });

  test('direct mount down: connection refused => server unavailable', () async {
    _installAdapter((o) => throw _connectionRefused(o));
    final result = await AudioServerHealthChecker.checkServerHealth(_directUrl);
    expect(result.isHealthy, isFalse);
    expect(result.errorType, AudioServerErrorType.serverUnavailable);
  });

  test('M3U host down: playlist fetch refused => server unavailable', () async {
    _installAdapter((o) {
      if (o.uri.toString().endsWith('.m3u')) throw _connectionRefused(o);
      return _ok('');
    });
    final result = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(result.isHealthy, isFalse);
    expect(result.errorType, AudioServerErrorType.serverUnavailable);
  });

  test('Icecast mount down: playlist OK but mount refused => unavailable',
      () async {
    _installAdapter((o) {
      if (o.uri.toString().endsWith('.m3u')) return _ok(_m3uBody);
      throw _connectionRefused(o);
    });
    final result = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(result.isHealthy, isFalse);
    expect(result.errorType, AudioServerErrorType.serverUnavailable);
  });

  test('mount returns 404 => stream not found', () async {
    _installAdapter((o) => ResponseBody.fromString('', 404));
    final result = await AudioServerHealthChecker.checkServerHealth(_directUrl);
    expect(result.isHealthy, isFalse);
    expect(result.errorType, AudioServerErrorType.streamNotFound);
  });

  // ---------------------------------------------------------------------
  // Which NOTICE the listener ends up seeing hangs off these branches:
  // an unhealthy result becomes the "outage" modal, while a thrown
  // NetworkConnectivityException becomes the retryable "connection" modal.
  // These were the untested paths behind the silent-failure bug.
  // ---------------------------------------------------------------------

  test('mount returns 503 => server overloaded (outage notice)', () async {
    _installAdapter((o) {
      if (o.uri.toString() == _m3uUrl) return _ok(_m3uBody);
      return ResponseBody.fromString('busy', 503);
    });
    final r = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(r.isHealthy, isFalse);
    expect(r.errorType, AudioServerErrorType.serverOverloaded);
  });

  test('mount returns 403 => auth error (outage notice)', () async {
    _installAdapter((o) {
      if (o.uri.toString() == _m3uUrl) return _ok(_m3uBody);
      return ResponseBody.fromString('denied', 403);
    });
    final r = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(r.isHealthy, isFalse);
    expect(r.errorType, AudioServerErrorType.authenticationError);
  });

  test('mount times out => connectionTimeout, not a crash', () async {
    _installAdapter((o) {
      if (o.uri.toString() == _m3uUrl) return _ok(_m3uBody);
      throw DioException(
          requestOptions: o, type: DioExceptionType.receiveTimeout);
    });
    final r = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(r.isHealthy, isFalse);
    expect(r.errorType, AudioServerErrorType.connectionTimeout);
  });

  test('captive-portal TLS interception => NetworkConnectivityException',
      () async {
    // A hotel/airport portal presenting its own certificate. This is the case
    // that used to fail SILENTLY: not a server outage, and the connectivity
    // probe still reads "online" because the portal answers with a 200 login
    // page. It must throw so the repository raises the connection notice.
    _installAdapter((o) {
      if (o.uri.toString() == _m3uUrl) return _ok(_m3uBody);
      throw DioException(
          requestOptions: o, type: DioExceptionType.badCertificate);
    });
    expect(
      () => AudioServerHealthChecker.checkServerHealth(_m3uUrl),
      throwsA(isA<NetworkConnectivityException>()),
    );
  });

  test('playlist host returns 500 => unhealthy, never reports healthy',
      () async {
    _installAdapter((o) => ResponseBody.fromString('server error', 500));
    final r = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(r.isHealthy, isFalse);
  });

  test('a failure is NEVER cached: the next probe re-checks and can recover',
      () async {
    // The "needs a reboot" bug: a single failure used to poison a static cache
    // so every later play reported unhealthy until the process was killed.
    var down = true;
    _installAdapter((o) {
      if (o.uri.toString() == _m3uUrl) return _ok(_m3uBody);
      if (down) throw _connectionRefused(o);
      return _ok('audio');
    });

    final first = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(first.isHealthy, isFalse);

    down = false; // station comes back
    final second = await AudioServerHealthChecker.checkServerHealth(_m3uUrl);
    expect(second.isHealthy, isTrue,
        reason: 'a stale failure must not lock playback out');
  });
}
