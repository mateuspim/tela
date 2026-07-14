import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// The only way the app talks to Wallhaven.
///
/// Owned by the domain, implemented in `data/` over Dio. Features depend on
/// this and never on the HTTP client, so replacing Dio touches one adapter.
/// Implementations throw [WallhavenFailure], never a transport exception.
///
/// ```dart
/// final WallpaperPage page = await api.search(const SearchQuery());
/// ```
abstract interface class WallhavenApi {
  /// Fetches one page of listings for [query].
  ///
  /// Throws [InvalidApiKeyFailure] if [query] asks for NSFW without a valid
  /// key, [RateLimitedFailure] once the 45 req/min ceiling is hit,
  /// [NetworkFailure] when Wallhaven is unreachable, and
  /// [UnexpectedResponseFailure] if the payload doesn't parse.
  Future<WallpaperPage> search(SearchQuery query);
}
