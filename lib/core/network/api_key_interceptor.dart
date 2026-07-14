import 'package:dio/dio.dart';
import 'package:tela/domain/ports/secret_store.dart';

/// Attaches the Wallhaven API key to every request, as a header.
///
/// This interceptor is the *only* place the key touches an HTTP request. It
/// goes in `X-API-Key` and never in the query string, because a query string
/// ends up in server logs, in crash reports, and in any URL we might print
/// (CLAUDE.md, hard rule).
///
/// Requests proceed without the header when no key is stored — SFW browsing
/// needs none.
class ApiKeyInterceptor extends Interceptor {
  /// Creates an interceptor reading the key from a [SecretStore].
  ApiKeyInterceptor(this._secrets);

  final SecretStore _secrets;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final String? key = await _secrets.readApiKey();
    if (key != null && key.isNotEmpty) {
      options.headers['X-API-Key'] = key;
    }
    handler.next(options);
  }
}
