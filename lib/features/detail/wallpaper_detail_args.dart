import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// What a wallpaper grid hands the detail route: the shelf to page through, and
/// the filters the user was browsing under when they tapped.
///
/// The second half is why this exists. A tag or colour followed *out* of the
/// detail screen must land in the same world the user was already in — sketchy
/// stays sketchy, People stays People — but the detail screen knows only the
/// one wallpaper, not the listing behind it. So the listing tells it, here, and
/// the detail screen forwards it whole to whatever it opens next (see
/// `WallpaperDetailScreen.originFilters`).
///
/// [originFilters] is optional: a curated shelf like Favorites has no "browse
/// filters" to inherit, and passing the bare session leaves a follow to fall
/// back to Browse's own filters, exactly as it did before this existed.
class WallpaperDetailArgs {
  /// Bundles a [session] with the [originFilters] it was opened from.
  const WallpaperDetailArgs({required this.session, this.originFilters});

  /// The ordered shelf snapshot the detail screen pages through.
  final GallerySessionController<Wallpaper> session;

  /// The filters of the listing this detail was opened from, or null when the
  /// shelf has none to inherit.
  final SearchQuery? originFilters;
}
