import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';

/// Fetches a page of wallpapers for a query.
///
/// Two things happen here that a bare [WallhavenApi] call would get wrong:
/// an NSFW query with no key is refused locally instead of burning one of the
/// 45 requests/min on a guaranteed 401, and the shuffle seed of a `random`
/// listing is carried into subsequent pages so scrolling doesn't repeat images.
///
/// ```dart
/// final WallpaperPage page = await searchWallpapers(const SearchQuery());
/// ```
class SearchWallpapers {
  /// Creates the use case. Both collaborators are injected (CLAUDE.md: no
  /// global singletons).
  const SearchWallpapers({
    required WallhavenApi api,
    required SecretStore secrets,
  }) : _api = api,
       _secrets = secrets;

  final WallhavenApi _api;
  final SecretStore _secrets;

  /// Runs [query], returning one page.
  ///
  /// Throws [InvalidApiKeyFailure] when [query] asks for NSFW and no key is
  /// stored — before any network call.
  Future<WallpaperPage> call(SearchQuery query) async {
    await _guardNsfwRequiresKey(query);
    return _api.search(query);
  }

  /// Runs [query] at the page after [previous], preserving its shuffle seed.
  ///
  /// Use this for infinite scroll rather than building the next query by hand;
  /// forgetting the seed on a `random` listing is a silent duplicate-images
  /// bug.
  Future<WallpaperPage> nextPageAfter(
    SearchQuery query,
    WallpaperPage previous,
  ) {
    final SearchQuery next = query
        .atPage(previous.currentPage + 1)
        .copyWith(seed: previous.seed ?? query.seed);
    return call(next);
  }

  Future<void> _guardNsfwRequiresKey(SearchQuery query) async {
    if (!query.purity.requiresApiKey) return;
    if (await _secrets.hasApiKey()) return;
    throw const InvalidApiKeyFailure(
      'nsfw purity requires a Wallhaven API key, but none is stored',
    );
  }
}
