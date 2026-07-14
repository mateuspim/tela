import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';

/// Keeps the app under Wallhaven's 45 requests/minute ceiling, and backs off
/// when it hits it anyway.
///
/// Two halves, because one without the other is not enough:
/// * a client-side sliding window that *delays* a request rather than letting
///   it become a 429 — the ceiling is shared across the whole app, and an
///   infinite-scroll grid can burn it in seconds;
/// * exponential backoff on a 429 that slipped through (another client on the
///   same IP, a clock skew, a burst we mis-counted).
class RateLimitInterceptor extends Interceptor {
  /// Creates an interceptor allowing [maxRequests] per [window].
  ///
  /// Defaults are Wallhaven's published limit with one request of headroom,
  /// since the server's minute and ours never line up exactly.
  ///
  /// [sleep] is injected so tests can run a full backoff sequence instantly
  /// instead of actually waiting seven seconds (F.I.R.S.T: fast).
  RateLimitInterceptor({
    this.maxRequests = 44,
    this.window = const Duration(minutes: 1),
    this.maxRetries = 3,
    Future<void> Function(Duration) sleep = _defaultSleep,
  }) : _sleep = sleep;

  /// The client used to replay a rate-limited request.
  ///
  /// Assigned by `WallhavenClient` right after the Dio instance exists — the
  /// reference is circular, so it cannot be a constructor argument. Replaying
  /// on a fresh `Dio()` instead would silently drop the configured base URL,
  /// timeouts, and the API-key header.
  late final Dio replayClient;

  /// How many requests are allowed per [window].
  final int maxRequests;

  /// The sliding window the limit applies over.
  final Duration window;

  /// How many times a 429 is retried before the failure is surfaced.
  final int maxRetries;

  final Future<void> Function(Duration) _sleep;

  /// Timestamps of in-window requests, oldest first.
  final Queue<DateTime> _recent = Queue<DateTime>();

  static Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await _waitForSlot();
    _recent.add(DateTime.now());
    handler.next(options);
  }

  /// Blocks until the sliding window has room for one more request.
  Future<void> _waitForSlot() async {
    _evictExpired();
    if (_recent.length < maxRequests) return;
    final Duration wait = window - DateTime.now().difference(_recent.first);
    if (wait > Duration.zero) await _sleep(wait);
    _evictExpired();
  }

  void _evictExpired() {
    final DateTime cutoff = DateTime.now().subtract(window);
    while (_recent.isNotEmpty && _recent.first.isBefore(cutoff)) {
      _recent.removeFirst();
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 429) {
      handler.next(err);
      return;
    }
    final int attempt = _attemptOf(err.requestOptions);
    if (attempt >= maxRetries) {
      handler.next(err);
      return;
    }
    await _sleep(_backoffFor(attempt));
    await _retry(err, attempt, handler);
  }

  /// 1s, 2s, 4s — doubling, so a sustained limit resolves without hammering.
  Duration _backoffFor(int attempt) =>
      Duration(milliseconds: 1000 * (1 << attempt));

  int _attemptOf(RequestOptions options) =>
      (options.extra[_attemptKey] as int?) ?? 0;

  Future<void> _retry(
    DioException err,
    int attempt,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions
      ..extra[_attemptKey] = attempt + 1;
    try {
      final Response<dynamic> response = await replayClient.fetch<dynamic>(
        options,
      );
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  static const String _attemptKey = 'tela.rateLimitRetryAttempt';
}
