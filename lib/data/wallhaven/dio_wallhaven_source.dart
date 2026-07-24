import 'package:dio/dio.dart';
import 'package:tela/data/wallhaven/wallhaven_mapper.dart';
import 'package:tela/data/wallhaven/wallhaven_query.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

/// Wallhaven, as a [WallpaperSource], over Dio.
///
/// Dio stops here: every `DioException` becomes a [SourceFailure], so no
/// feature ever imports the HTTP client to find out what went wrong, and
/// swapping Dio out touches only this file (CLAUDE.md, dependency rule).
class DioWallhavenSource implements WallpaperSource {
  /// Creates the adapter over a configured [Dio] (see `WallhavenClient`).
  const DioWallhavenSource(this._dio);

  final Dio _dio;

  @override
  SourceId get id => SourceId.wallhaven;

  @override
  String get displayName => 'Wallhaven';

  /// Everything Wallhaven's `/search` honours, and nothing it doesn't.
  ///
  /// The whole filter vocabulary is here because Wallhaven is the source tela
  /// was built around; a second source declaring less is what proves the sheet
  /// really renders from this rather than from habit.
  @override
  SourceCapabilities get capabilities => const SourceCapabilities(
    filters: <SourceFilter>{
      SourceFilter.categories,
      SourceFilter.purity,
      SourceFilter.colors,
      SourceFilter.ratios,
      SourceFilter.resolutions,
      SourceFilter.tags,
      SourceFilter.order,
      SourceFilter.topRange,
    },
    sortings: <Sorting>{
      Sorting.dateAdded,
      Sorting.relevance,
      Sorting.random,
      Sorting.views,
      Sorting.favorites,
      Sorting.toplist,
      Sorting.hot,
    },
    purities: <Purity>{Purity.sfw, Purity.sketchy, Purity.nsfw},
    credentials: SourceCredentials.nsfwRequiresKey,
    // The published ceiling. The interceptor throttles to it; a 429 still
    // backs off exponentially rather than trusting any Retry-After blindly.
    requestsPerMinute: 45,
    syncsAccountDefaults: true,
  );

  @override
  Future<WallpaperPage> search(SearchQuery query) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>(
            '/search',
            queryParameters: wallhavenQueryParameters(query),
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
