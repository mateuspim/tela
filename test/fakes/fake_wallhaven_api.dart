import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';

/// In-memory [WallhavenApi] that records what it was asked for.
///
/// Records every [SearchQuery] it receives so tests can assert on the request
/// the use case *built*, which is where the seed and paging bugs live.
class FakeWallhavenApi implements WallhavenApi {
  /// Creates a fake that answers every search with [page], or throws [failure].
  FakeWallhavenApi({this.page, this.details, this.failure});

  /// The page every [search] returns, unless [failure] is set.
  final WallpaperPage? page;

  /// The detail response returned for every wallpaper id.
  final WallpaperDetails? details;

  /// When set, every call throws this instead of returning a page.
  final WallhavenFailure? failure;

  /// Every query passed to [search], oldest first.
  final List<SearchQuery> receivedQueries = <SearchQuery>[];

  @override
  Future<WallpaperPage> search(SearchQuery query) async {
    receivedQueries.add(query);
    final WallhavenFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return page ??
        const WallpaperPage(
          wallpapers: <Wallpaper>[],
          currentPage: 1,
          lastPage: 1,
        );
  }

  @override
  Future<WallpaperDetails> wallpaperDetails(String id) async {
    final WallhavenFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    final WallpaperDetails? result = details;
    if (result == null) {
      throw const UnexpectedResponseFailure('Fake has no detail response');
    }
    return result;
  }
}
