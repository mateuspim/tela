import 'package:dio/dio.dart';
import 'package:tela/data/wallhaven/wallhaven_mapper.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';

/// The Dio-backed [WallhavenApi].
///
/// Dio stops here: every `DioException` becomes a [SourceFailure], so no
/// feature ever imports the HTTP client to find out what went wrong, and
/// swapping Dio out touches only this file (CLAUDE.md, dependency rule).
class DioWallhavenApi implements WallhavenApi {
  /// Creates the adapter over a configured [Dio] (see `WallhavenClient`).
  const DioWallhavenApi(this._dio);

  final Dio _dio;

  @override
  Future<WallpaperPage> search(SearchQuery query) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>(
            '/search',
            queryParameters: query.toQueryParameters(),
          );
      return _mapped(response.data, WallhavenMapper.toPage);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  @override
  Future<WallpaperDetails> wallpaperDetails(String id) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>('/w/$id');
      return _mapped(response.data, WallhavenMapper.toDetails);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  @override
  Future<AccountSettings> accountSettings() async {
    try {
      // No query string: the key rides the X-API-Key header, the way every
      // other request here does. Wallhaven documents `?apikey=` for this
      // endpoint and accepts the header too — the header is the rule.
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>('/settings');
      return _mapped(response.data, WallhavenMapper.toAccountSettings);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  /// Runs [map] over a body Dio decoded, refusing an empty one.
  ///
  /// A 200 with no body is not something any of the three endpoints does, and
  /// mapping it would be a null-check inside each mapper instead of one here.
  T _mapped<T>(
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic> body) map,
  ) {
    if (body == null) {
      throw const UnexpectedResponseFailure('Wallhaven returned an empty body');
    }
    return map(body);
  }

  /// Translates transport-level noise into the four things the UI can act on.
  SourceFailure _toFailure(DioException error) {
    final int? status = error.response?.statusCode;
    if (status == 401) return const InvalidApiKeyFailure();
    if (status == 429) {
      return RateLimitedFailure(
        retryAfter: _retryAfterOf(error.response),
        message: 'Wallhaven rate limit reached (45 req/min)',
      );
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.connectionError => const NetworkFailure(),
      // Deliberately not interpolating the URL: it is the one string that could
      // carry a key if someone ever regresses the header rule.
      _ => UnexpectedResponseFailure(
        'Wallhaven answered with status ${status ?? 'none'}',
      ),
    };
  }

  Duration? _retryAfterOf(Response<dynamic>? response) {
    final String? header = response?.headers.value('retry-after');
    final int? seconds = header == null ? null : int.tryParse(header);
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
