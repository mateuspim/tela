import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';

/// Walks a listing from its first page to its last, handing over each page as
/// it arrives.
///
/// **The point is that nothing accumulates.** Downloading a whole tag was
/// otherwise a choice between two bad shapes: load every wallpaper into the
/// wall so the existing selection could tick them — tens of thousands of tiles
/// in a list that is already the app's memory pressure — or hold the whole
/// listing in a variable, which is the same cost without the tiles. Handing
/// each page straight to `onPage` lets the caller commit it to the durable
/// download queue and forget it, so a 12,000-wallpaper listing costs one page
/// of memory at a time.
///
/// Paging goes through [SearchWallpapers]'s `nextPageAfter`, so the shuffle
/// seed of a `random` listing is carried and the walk cannot re-roll into
/// wallpapers it has already handed over.
///
/// **This walk is not durable.** What `onPage` enqueues survives the process;
/// the walk itself does not, so a listing abandoned at page 9 of 18 has queued
/// nine pages and forgotten the rest. That is a deliberate first cut — the
/// queue's own durability covers the expensive half (the downloads), and a
/// resumable walk needs a stored cursor that nothing else yet wants.
///
/// ```dart
/// final int walked = await WalkListingPages(search: search)(
///   query,
///   onPage: (List<Wallpaper> page) => queue.enqueue(page),
///   isCancelled: () => stopped,
/// );
/// ```
class WalkListingPages {
  /// Creates the use case.
  const WalkListingPages({required SearchWallpapers search}) : _search = search;

  final SearchWallpapers _search;

  /// How many pages a single walk will request before giving up.
  ///
  /// A runaway guard, not a product limit: [WallpaperPage.hasMore] comes from
  /// the source, and a source that answers true forever — a bug, a proxy, a
  /// mangled response — would otherwise page until the user's rate limit ran
  /// out and then keep going. At Wallhaven's 24 per page this is 12,000
  /// wallpapers, well past any listing anyone has asked to download whole.
  static const int defaultMaxPages = 500;

  /// Walks [query]'s listing, awaiting `onPage` for each page in order.
  ///
  /// Returns how many wallpapers were handed over. Stops early when
  /// `isCancelled` answers true — checked before each request *and* before each
  /// hand-over, so a cancel lands within one page rather than at the end.
  ///
  /// Pass `after` to resume from the page following one the caller already
  /// holds. The confirmation before a bulk download has to fetch page 1 to know
  /// how big the listing is, and re-fetching it here would spend a second
  /// request off a 45-per-minute budget to learn what is already in hand — and
  /// on a `random` listing would re-roll the shuffle while doing it.
  ///
  /// Throws whatever the source throws. A failure mid-walk leaves the pages
  /// already handed to `onPage` in place, which is the honest outcome: they
  /// are queued, and the queue is where their fate is now reported.
  Future<int> call(
    SearchQuery query, {
    required Future<void> Function(List<Wallpaper> page) onPage,
    WallpaperPage? after,
    bool Function()? isCancelled,
    int maxPages = defaultMaxPages,
  }) async {
    if (after != null && !after.hasMore) return 0;
    int walked = 0;
    WallpaperPage? previous = after;
    for (int page = 0; page < maxPages; page++) {
      if (isCancelled?.call() ?? false) return walked;
      final WallpaperPage current = await _fetch(query, previous);
      if (isCancelled?.call() ?? false) return walked;
      if (current.wallpapers.isNotEmpty) {
        await onPage(current.wallpapers);
        walked += current.wallpapers.length;
      }
      if (!current.hasMore) return walked;
      previous = current;
    }
    return walked;
  }

  /// The first page, or the one after [previous] with its seed carried.
  Future<WallpaperPage> _fetch(SearchQuery query, WallpaperPage? previous) {
    if (previous == null) return _search(query.atPage(1));
    return _search.nextPageAfter(query, previous);
  }
}
