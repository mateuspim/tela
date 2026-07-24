import 'package:dio/dio.dart';
import 'package:tela/data/konachan/konachan_mapper.dart';
import 'package:tela/data/konachan/konachan_query.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

/// Konachan, as a [WallpaperSource], over Dio (PLAN §18).
///
/// Dio stops here: every `DioException` becomes a [SourceFailure], so no
/// feature imports the HTTP client, and swapping Dio touches only this file
/// (CLAUDE.md).
/// The host is chosen per request from the query's purity — SFW-only reads the
/// server-enforced-safe `.net`, so a bug in rating mapping cannot leak an
/// explicit image into a safe browse (PLAN §18.2).
class DioKonachanSource implements WallpaperSource {
  /// Creates the adapter over a configured [Dio] (see `KonachanClient`).
  const DioKonachanSource(this._dio);

  final Dio _dio;

  @override
  SourceId get id => SourceId.konachan;

  @override
  String get displayName => 'Konachan';

  /// The booru-shaped subset of what tela can ask — deliberately narrower than
  /// Wallhaven's, and the thing that makes the capability-driven filter sheet
  /// do something a human can see.
  ///
  /// No categories or colours (Konachan has neither axis), no toplist range,
  /// and three sortings only: `random` takes no seed and would repeat images
  /// across pages, so it is left out rather than shipped broken (PLAN §18.3).
  @override
  SourceCapabilities get capabilities => const SourceCapabilities(
    filters: <SourceFilter>{
      SourceFilter.purity,
      SourceFilter.ratios,
      SourceFilter.resolutions,
      SourceFilter.tags,
    },
    sortings: <Sorting>{Sorting.dateAdded, Sorting.views, Sorting.favorites},
    purities: <Purity>{Purity.sfw, Purity.sketchy, Purity.nsfw},
    // Explicit content is served anonymously — refusing it for want of a key
    // would refuse a request Konachan would happily answer (PLAN §18.5).
    credentials: SourceCredentials.none,
    requestsPerMinute: 60,
    syncsAccountDefaults: false,
  );

  @override
  Future<WallpaperPage> search(SearchQuery query) async {
    final String host = KonachanHost.forPurity(query.purity);
    try {
      final Response<List<dynamic>> response = await _dio.get<List<dynamic>>(
        'https://$host/post.json',
        queryParameters: konachanQueryParameters(query),
      );
      return KonachanMapper.toPage(response.data, currentPage: query.page);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  @override
  Future<WallpaperDetails> wallpaperDetails(String id) async {
    try {
      // Always the unrestricted host: `.net` returns [] for a questionable or
      // explicit post, which would surface as a mystery empty detail screen
      // rather than the wallpaper the user opened (PLAN §18.4).
      final Response<List<dynamic>> response = await _dio.get<List<dynamic>>(
        'https://${KonachanHost.unrestricted}/post.json',
        queryParameters: <String, String>{'tags': 'id:$id', 'limit': '1'},
      );
      return KonachanMapper.toDetails(response.data);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  @override
  Future<AccountSettings> accountSettings() {
    // Konachan has no accounts, and the capability says so. Reaching here
    // without asking `syncsAccountDefaults` first is a programming error.
    throw UnsupportedError(
      'Konachan has no account defaults to sync; '
      'guard on SourceCapabilities.syncsAccountDefaults',
    );
  }

  /// Translates transport-level noise into the failures the UI can act on.
  ///
  /// No 401 branch: Konachan needs no key, so a rejected request is never an
  /// invalid-key one. A Cloudflare challenge arrives as an ordinary non-2xx
  /// with an HTML body and lands in [UnexpectedResponseFailure].
  SourceFailure _toFailure(DioException error) {
    final int? status = error.response?.statusCode;
    if (status == 429) {
      return RateLimitedFailure(
        retryAfter: _retryAfterOf(error.response),
        message: 'Konachan rate limit reached (60 req/min)',
      );
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.connectionError => const NetworkFailure(),
      _ => UnexpectedResponseFailure(
        'Konachan answered with status ${status ?? 'none'}',
      ),
    };
  }

  Duration? _retryAfterOf(Response<dynamic>? response) {
    final String? header = response?.headers.value('retry-after');
    final int? seconds = header == null ? null : int.tryParse(header);
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
