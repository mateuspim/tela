import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';

/// What the collection-listing route carries: which collection, and the
/// filters it was opened under.
///
/// The whole [WallpaperCollection] rather than its [CollectionRef], because
/// the listing screen prints the label and needs `count` to say how much of it
/// the purity filter is withholding — neither of which a ref carries, and
/// re-fetching the row to learn them would be a second request for something
/// the caller already had in its hand.
class CollectionListingArgs {
  /// Bundles the [collection] to open with the [seed] filters to open it under.
  const CollectionListingArgs({required this.collection, this.seed});

  /// The collection to show.
  final WallpaperCollection collection;

  /// The filters of the listing it was opened from, or null.
  ///
  /// Only the purity is used — it is the only filter the endpoint honours —
  /// but the whole query is carried so the rule lives in one place, the
  /// listing screen, rather than at every call site.
  final SearchQuery? seed;
}
