import 'package:dio/dio.dart';
import 'package:tela/data/wallhaven/wallhaven_mapper.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';

/// The Dio-backed [WallhavenApi].
///
/// Dio stops here: every `DioException` becomes a [WallhavenFailure], so no
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
      return _mapBody(response.data);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  WallpaperPage _mapBody(Map<String, dynamic>? body) {
    if (body == null) {
      throw const UnexpectedResponseFailure('Wallhaven returned an empty body');
    }
    return WallhavenMapper.toPage(body);
  }

  /// Translates transport-level noise into the four things the UI can act on.
  WallhavenFailure _toFailure(DioException error) {
    final int? status = error.response?.statusCode;
    if (status == 401) return const InvalidApiKeyFailure();
    if (status == 429) {
      return RateLimitedFailure(retryAfter: _retryAfterOf(error.response));
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
