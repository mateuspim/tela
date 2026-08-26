import 'package:tela/domain/models/search_query.dart';

/// What the collections route carries: whose collections, and under which
/// filters to open the ones that are tapped.
///
/// Every field is optional, because the no-argument case is real and is the
/// one a menu entry uses: no username means *mine*, read from settings.
class CollectionsArgs {
  /// Bundles [username] with the [seed] filters its collections open under.
  const CollectionsArgs({this.username, this.seed});

  /// Whose collections to list. Null means the stored username's.
  final String? username;

  /// The filters of the listing this was reached from, or null.
  final SearchQuery? seed;
}
