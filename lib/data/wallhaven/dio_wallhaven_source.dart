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

  /// One `/w/{id}` per wallpaper, stopped at [budget].
  ///
  /// Wallhaven's `/search` carries no tags whatsoever — they exist only on the
  /// per-wallpaper endpoint — so unlike a booru there is nothing already paid
  /// for to read from. Every answer here is a request against the 45/minute
  /// ceiling, which is why the budget is small and the caller shows whatever
  /// arrives: a hundred-wallpaper batch must not spend two minutes and the
  /// whole rate allowance on *suggestions* before the downloads that need it.
  ///
  /// Sequential rather than concurrent on purpose. `RateLimitInterceptor`
  /// paces the whole app from one window, so firing twenty at once only queues
  /// them behind each other while making a 429 likelier — and this runs while
  /// the user is looking at a dialog that already opened.
  @override
  Future<Map<String, List<WallpaperTag>>> tagsFor(
    List<String> ids, {
    required int budget,
  }) async {
    final Map<String, List<WallpaperTag>> found =
        <String, List<WallpaperTag>>{};
    for (final String id in ids.take(budget)) {
      try {
        found[id] = (await wallpaperDetails(id)).tags;
      } on SourceFailure {
        // A wallpaper that will not load costs its own suggestions only. A
        // rate-limited or offline source ends up answering an empty map, and
        // the chooser simply has nothing extra to offer.
        continue;
      }
    }
    return found;
  }

  @override
  Future<WallpaperDetails> wallpaperDetails(String id) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>('/w/$id');
      return _mapped(response.data, WallhavenMapper.toDetails);
    } on DioException catch (error) {
      throw _toFailure(error, notFoundId: id);
    }
  }

  /// Six characters of Wallhaven's own alphabet, case-folded.
  ///
  /// The alphabet is `0-9` plus `degjklmnopqrvwxyz` — measured off 623 live ids
  /// (3738 characters), in which `a b c f h i s t u` never once appear, so this
  /// is Wallhaven's issuing alphabet and not a sample artefact. Dropping those
  /// nine letters is what keeps the chip quiet on ordinary six-letter searches:
  /// `sunset`, `nature`, `forest`, `castle` and `purple` all contain one.
  static final RegExp _idShape = RegExp(r'^[0-9degjklmnopqrvwxyz]{6}$');

  /// Lowercases before matching: `GET /w/Je9ldp` is a 404 and `/w/je9ldp` is
  /// the wallpaper, so a soft keyboard's auto-capital would otherwise make
  /// every typed id miss.
  @override
  String? wallpaperIdIn(String text) {
    final String candidate = text.trim().toLowerCase();
    return _idShape.hasMatch(candidate) ? candidate : null;
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

  /// Translates transport-level noise into the things the UI can act on.
  ///
  /// [notFoundId] is passed only by a single-wallpaper lookup, and only then
  /// does a 404 mean "no such wallpaper": a 404 from `/search` or `/settings`
  /// is Wallhaven answering strangely, not a missing id, and stays an
  /// [UnexpectedResponseFailure].
  SourceFailure _toFailure(DioException error, {String? notFoundId}) {
    final int? status = error.response?.statusCode;
    if (status == 401) return const InvalidApiKeyFailure();
    if (status == 404 && notFoundId != null) {
      return NotFoundFailure(notFoundId);
    }
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
