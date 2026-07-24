import 'package:dio/dio.dart';
import 'package:tela/core/network/rate_limit_interceptor.dart';

/// Builds the one configured Dio instance the app talks to Konachan with.
///
/// Unlike `WallhavenClient`, this sets **no** base URL: Konachan serves one
/// post database on two hosts and the adapter picks between them per request
/// from the query's purity (`KonachanHost.forPurity`, PLAN §18.2), so every
/// request goes out as an absolute URL. No API-key interceptor either —
/// Konachan needs no credentials and serves explicit content anonymously
/// (PLAN §18.5).
abstract final class KonachanClient {
  /// A real User-Agent. Boorus commonly reject a default or absent one, and a
  /// Cloudflare challenge arrives as an unparseable HTML body rather than a
  /// clean failure (PLAN §18.5).
  static const String userAgent = 'tela wallpaper browser';

  /// One request of headroom under Konachan's conservative 60/min ceiling —
  /// there are no `X-RateLimit-*` headers to pace against, so the client stays
  /// deliberately under the line (PLAN §18.5).
  static const int _maxRequestsPerMinute = 59;

  /// Creates the client.
  ///
  /// ```dart
  /// final Dio dio = KonachanClient.create();
  /// ```
  static Dio create() {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: <String, String>{'User-Agent': userAgent},
      ),
    );
    final RateLimitInterceptor limiter = RateLimitInterceptor(
      maxRequests: _maxRequestsPerMinute,
    )..replayClient = dio;
    dio.interceptors.add(limiter);
    return dio;
  }
}
