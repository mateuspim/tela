import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/network/rate_limit_interceptor.dart';

/// Records how long the interceptor asked to sleep, without ever sleeping.
class RecordingSleeper {
  /// Every requested delay, in order.
  final List<Duration> slept = <Duration>[];

  /// Drop-in for the interceptor's `sleep`, returning immediately.
  Future<void> call(Duration duration) async => slept.add(duration);
}

void main() {
  group('RateLimitInterceptor throttling', () {
    test('lets requests through while under the window limit', () async {
      final RecordingSleeper sleeper = RecordingSleeper();
      final RateLimitInterceptor interceptor = RateLimitInterceptor(
        maxRequests: 3,
        sleep: sleeper.call,
      );

      for (int i = 0; i < 3; i++) {
        await interceptor.onRequest(
          RequestOptions(path: '/search'),
          RequestInterceptorHandler(),
        );
      }

      expect(sleeper.slept, isEmpty);
    });

    test('delays the request that would exceed the window', () async {
      final RecordingSleeper sleeper = RecordingSleeper();
      final RateLimitInterceptor interceptor = RateLimitInterceptor(
        maxRequests: 2,
        sleep: sleeper.call,
      );

      for (int i = 0; i < 3; i++) {
        await interceptor.onRequest(
          RequestOptions(path: '/search'),
          RequestInterceptorHandler(),
        );
      }

      // The third request waits rather than becoming a 429 — an infinite-scroll
      // grid can burn 45 req/min in seconds.
      expect(sleeper.slept, hasLength(1));
      expect(
        sleeper.slept.single,
        lessThanOrEqualTo(const Duration(minutes: 1)),
      );
      expect(sleeper.slept.single, greaterThan(Duration.zero));
    });

    test("defaults to below Wallhaven's published ceiling", () {
      // The server's minute and ours never line up exactly; the headroom is
      // what stops a boundary tick from 429ing.
      expect(RateLimitInterceptor().maxRequests, lessThan(45));
    });
  });

  group('RateLimitInterceptor backoff', () {
    test('backs off exponentially on 429, then gives up', () async {
      final RecordingSleeper sleeper = RecordingSleeper();
      // maxRetries left at its default of 3 — that default is what ships.
      final RateLimitInterceptor interceptor = RateLimitInterceptor(
        sleep: sleeper.call,
      );
      // A client that always 429s, so every retry fails and we see the full
      // backoff sequence.
      final Dio alwaysLimited = Dio()
        ..httpClientAdapter = _AlwaysStatusAdapter(429);
      interceptor.replayClient = alwaysLimited;

      await _drive429(interceptor);

      expect(sleeper.slept, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
    });

    test('ignores errors that are not rate limits', () async {
      final RecordingSleeper sleeper = RecordingSleeper();
      final RateLimitInterceptor interceptor = RateLimitInterceptor(
        sleep: sleeper.call,
      );
      final DioException notFound = DioException(
        requestOptions: RequestOptions(path: '/search'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/search'),
          statusCode: 404,
        ),
      );

      await interceptor.onError(notFound, _CapturingErrorHandler());

      expect(sleeper.slept, isEmpty);
    });
  });
}

/// Runs a 429 through the interceptor until it stops retrying.
Future<void> _drive429(RateLimitInterceptor interceptor) async {
  final RequestOptions options = RequestOptions(path: '/search');
  DioException error() => DioException(
    requestOptions: options,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: 429,
    ),
  );

  for (int attempt = 0; attempt <= interceptor.maxRetries; attempt++) {
    await interceptor.onError(error(), _CapturingErrorHandler());
  }
}

/// Swallows the handler's outcome instead of completing Dio's internal future.
///
/// A bare [ErrorInterceptorHandler] completes that future *with an error*, and
/// with nothing awaiting it the test dies on an uncaught async error rather
/// than on the assertion it was written for.
class _CapturingErrorHandler extends ErrorInterceptorHandler {
  @override
  void next(DioException err) {}

  @override
  void reject(
    DioException error, [
    bool callFollowingErrorInterceptor = false,
  ]) {}

  @override
  void resolve(Response<dynamic> response) {}
}

/// An adapter that answers every request with a fixed status.
class _AlwaysStatusAdapter implements HttpClientAdapter {
  _AlwaysStatusAdapter(this.status);

  final int status;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('', status);
  }
}
