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
    required this.lastPage,
    this.seed,
  });

  /// The wallpapers on this page, in Wallhaven's order.
  final List<Wallpaper> wallpapers;

  /// 1-based index of this page.
  final int currentPage;

  /// Index of the final page for this query.
  final int lastPage;

  /// Wallhaven's shuffle seed for `random` sortings. Carrying it into the next
  /// page request is what stops page 2 from re-rolling the shuffle and
  /// repeating images already shown.
  final String? seed;

  /// Whether another page exists.
  bool get hasMore => currentPage < lastPage;
}
