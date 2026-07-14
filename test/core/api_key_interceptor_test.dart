import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/network/api_key_interceptor.dart';

import '../fakes/fake_secret_store.dart';

/// Captures the options a request would have gone out with.
Future<RequestOptions> _runInterceptor(ApiKeyInterceptor interceptor) async {
  final RequestOptions options = RequestOptions(path: '/search');
  final Completer<RequestOptions> captured = Completer<RequestOptions>();
  await interceptor.onRequest(options, _CapturingHandler(captured));
  return captured.future;
}

class _CapturingHandler extends RequestInterceptorHandler {
  _CapturingHandler(this._captured);

  final Completer<RequestOptions> _captured;

  @override
  void next(RequestOptions requestOptions) =>
      _captured.complete(requestOptions);
}

void main() {
  group('ApiKeyInterceptor', () {
    test('sends the key in the X-API-Key header', () async {
      final ApiKeyInterceptor interceptor = ApiKeyInterceptor(
        FakeSecretStore(storedKey: 'secret-key'),
      );

      final RequestOptions options = await _runInterceptor(interceptor);

      expect(options.headers['X-API-Key'], 'secret-key');
    });

    test('never puts the key in the query string', () async {
      final ApiKeyInterceptor interceptor = ApiKeyInterceptor(
        FakeSecretStore(storedKey: 'secret-key'),
      );

      final RequestOptions options = await _runInterceptor(interceptor);

      // A key in the query string ends up in server logs and crash reports.
      // CLAUDE.md makes this a hard rule; this test is the enforcement.
      expect(options.queryParameters, isEmpty);
      expect(options.uri.toString(), isNot(contains('secret-key')));
    });

    test('sends no header at all when no key is stored', () async {
      final ApiKeyInterceptor interceptor = ApiKeyInterceptor(
        FakeSecretStore(),
      );

      final RequestOptions options = await _runInterceptor(interceptor);

      // SFW browsing must work with no key.
      expect(options.headers.containsKey('X-API-Key'), isFalse);
    });
  });
}
