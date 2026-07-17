import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_link.dart';

/// What the detail screen hands the linked-listing route: the link to follow,
/// and the filters to open it under.
///
/// A followed listing is newest-first and narrowed to the link — its tag,
/// uploader, or colour (see [WallpaperLink.narrow]) — but every other filter,
/// purity above all, is inherited from wherever the user followed it. [seed]
/// carries those. Null
/// means "no origin to inherit", and the screen falls back to Browse's own
/// filters, the same starting point arriving from Browse gives.
class LinkedListingArgs {
  /// Bundles the [link] to follow with the [seed] filters to open it under.
  const LinkedListingArgs({required this.link, this.seed});

  /// The tag or uploader followed.
  final WallpaperLink link;

  /// The filters of the listing the link was followed from, or null.
  final SearchQuery? seed;
}
