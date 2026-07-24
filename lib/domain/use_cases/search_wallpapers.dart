import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';

/// Fetches a page of wallpapers for a query.
///
/// Three things happen here that a bare [WallhavenApi] call would get wrong:
/// an NSFW query with no key is refused locally instead of burning one of the
/// 45 requests/min on a guaranteed 401, the shuffle seed of a `random` listing
/// is carried into subsequent pages so scrolling doesn't repeat images, and
/// every tag on the user's blocklist is folded in as an exclude — so blocking
/// a tag once keeps it out of the search box, every browse tab, and every
/// followed listing alike, with no feature having to remember to ask.
///
/// ```dart
/// final WallpaperPage page = await searchWallpapers(const SearchQuery());
/// ```
class SearchWallpapers {
  /// Creates the use case. Every collaborator is injected (CLAUDE.md: no
  /// global singletons).
  const SearchWallpapers({
    required WallhavenApi api,
    required SecretStore secrets,
    required TagBlocklistRepository blocklist,
  }) : _api = api,
       _secrets = secrets,
       _blocklist = blocklist;

  final WallhavenApi _api;
  final SecretStore _secrets;
  final TagBlocklistRepository _blocklist;

  /// Runs [query], returning one page.
  ///
  /// Throws [InvalidApiKeyFailure] when [query] asks for NSFW and no key is
  /// stored — before any network call.
  Future<WallpaperPage> call(SearchQuery query) async {
    await _guardNsfwRequiresKey(query);
    final Set<String> blocked = await _blocklist.blockedNames();
    return _api.search(query.copyWith(blockedTagNames: blocked));
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
