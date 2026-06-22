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
}
