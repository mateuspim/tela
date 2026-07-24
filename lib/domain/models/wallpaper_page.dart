import 'package:tela/domain/models/wallpaper.dart';

/// One page of results, plus what the pager needs to fetch the next one.
///
/// ```dart
/// final WallpaperPage page = await api.search(query);
/// if (page.hasMore) fetch(query.atPage(page.currentPage + 1));
/// ```
class WallpaperPage {
  /// Creates a page of results.
  const WallpaperPage({
    required this.wallpapers,
    required this.currentPage,
    required this.hasMore,
    this.lastPage,
    this.seed,
  });

  /// The wallpapers on this page, in the source's order.
  final List<Wallpaper> wallpapers;

  /// 1-based index of this page.
  final int currentPage;

  /// Whether another page exists.
  ///
  /// The stored primitive rather than something derived from [lastPage],
  /// because not every source has a page count: the Moebooru family (Konachan)
  /// returns a bare JSON array with no metadata at all, and you learn you are
  /// at the end by receiving a short page. Verified live, 2026-07-24 — PLAN
  /// §18.1.
  final bool hasMore;

  /// Index of the final page for this query, where the source publishes one.
  ///
  /// Null is not "no more pages" — it is "this source does not count them".
  /// Nothing paginates on it; it is here for a UI that wants to say how far a
  /// listing runs.
  final int? lastPage;

  /// The source's shuffle seed for `random` sortings. Carrying it into the next
  /// page request is what stops page 2 from re-rolling the shuffle and
  /// repeating images already shown.
  final String? seed;
}
