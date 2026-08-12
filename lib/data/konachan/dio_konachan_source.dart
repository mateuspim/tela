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
  DioKonachanSource(
    this._dio, {
    Future<void> Function(Duration) delay = Future<void>.delayed,
  }) : _delay = delay;

  final Dio _dio;
  final Future<void> Function(Duration) _delay;

  /// One short retry turns the transient timeout seen on hardware into a
  /// slightly slower successful fetch without hiding a persistent outage.
  static const Duration _networkRetryDelay = Duration(milliseconds: 500);

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
      final Response<List<dynamic>> response = await _getPosts(
        'https://$host/post.json',
        queryParameters: konachanQueryParameters(query),
      );
      _rememberTags(response.data);
      return KonachanMapper.toPage(response.data, currentPage: query.page);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  /// Retries one idempotent listing read after a transport-level failure.
  ///
  /// Konachan sits behind Cloudflare and the tablet produced one receive
  /// timeout that succeeded immediately when retried. Status responses are not
  /// retried here: 429 has its own limiter path, and repeating a 4xx/5xx would
  /// spend source budget without changing the answer.
  Future<Response<List<dynamic>>> _getPosts(
    String url, {
    required Map<String, String> queryParameters,
  }) async {
    try {
      return await _dio.get<List<dynamic>>(
        url,
        queryParameters: queryParameters,
      );
    } on DioException catch (error) {
      if (!_isTransientNetworkFailure(error)) rethrow;
      await _delay(_networkRetryDelay);
      return _dio.get<List<dynamic>>(
        url,
        queryParameters: queryParameters,
      );
    }
  }

  bool _isTransientNetworkFailure(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.connectionError => true,
      _ => false,
    };
  }

  /// Tags read off the listings this adapter has already fetched.
  ///
  /// A booru's search response carries every post's tags, so the grid the user
  /// is selecting from has *already* paid for them. Keeping them here is what
  /// makes [tagsFor] free for a visible selection — the alternative is one
  /// `id:{n}` search per wallpaper, since Konachan has no per-post endpoint at
  /// all (PLAN §18.1).
  ///
  /// Bounded and oldest-first-evicted: an infinite scroll would otherwise grow
  /// this without limit, and a tag map for a wallpaper the user scrolled past
  /// twenty pages ago is not worth the memory. Dart's map preserves insertion
  /// order, which is what makes the eviction a one-liner.
  final Map<String, List<WallpaperTag>> _listingTags =
      <String, List<WallpaperTag>>{};

  /// Roughly ten pages of a booru listing. Comfortably more than any selection
  /// the user can make on screen, and small enough to be uninteresting.
  static const int _maxRememberedTags = 500;

  void _rememberTags(Object? body) {
    _listingTags.addAll(KonachanMapper.tagsIn(body));
    while (_listingTags.length > _maxRememberedTags) {
      _listingTags.remove(_listingTags.keys.first);
    }
  }

  /// Answers from the listings already fetched, spending requests only on ids
  /// never seen. See [WallpaperSource.tagsFor].
  @override
  Future<Map<String, List<WallpaperTag>>> tagsFor(
    List<String> ids, {
    required int budget,
  }) async {
    final Map<String, List<WallpaperTag>> found = <String, List<WallpaperTag>>{
      for (final String id in ids)
        if (_listingTags[id] case final List<WallpaperTag> tags) id: tags,
    };
    int spent = 0;
    for (final String id in ids) {
      if (found.containsKey(id) || spent >= budget) continue;
      spent++;
      try {
        found[id] = (await wallpaperDetails(id)).tags;
      } on SourceFailure {
        // One unreachable wallpaper costs its own suggestions and no others.
        continue;
      }
    }
    return found;
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
      return KonachanMapper.toDetails(response.data, id: id);
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  /// A decimal post number, the only id shape a Moebooru issues.
  ///
  /// No leading zero (`id:0406584` is not how Konachan writes one) and bounded
  /// at nine digits, which keeps it inside an int and well past the ~400k posts
  /// the site actually has.
  static final RegExp _idShape = RegExp(r'^[1-9][0-9]{0,8}$');

  @override
  String? wallpaperIdIn(String text) {
    final String candidate = text.trim();
    return _idShape.hasMatch(candidate) ? candidate : null;
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
