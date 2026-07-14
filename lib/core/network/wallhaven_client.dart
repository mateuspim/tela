import 'package:dio/dio.dart';
import 'package:tela/core/network/api_key_interceptor.dart';
import 'package:tela/core/network/rate_limit_interceptor.dart';
import 'package:tela/domain/ports/secret_store.dart';

/// Builds the one configured Dio instance the app talks to Wallhaven with.
///
/// Kept separate from the API adapter so the interceptor wiring — key header,
/// rate limit — is stated in one readable place instead of being buried in a
/// constructor.
abstract final class WallhavenClient {
  /// Wallhaven's API root. Every path in the adapter is relative to this.
  static const String baseUrl = 'https://wallhaven.cc/api/v1';

  /// Creates the client, reading the API key from [secrets].
  ///
  /// ```dart
  /// final Dio dio = WallhavenClient.create(secrets: secretStore);
  /// ```
  static Dio create({required SecretStore secrets}) {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final RateLimitInterceptor limiter = RateLimitInterceptor()
      ..replayClient = dio;
    dio.interceptors.addAll(<Interceptor>[ApiKeyInterceptor(secrets), limiter]);
    return dio;
  }
}
