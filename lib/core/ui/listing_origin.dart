import 'package:flutter/widgets.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/use_cases/suggest_tag_folders.dart';

/// The listing a download taken from this subtree is being taken *from*.
///
/// Published by every shelf that is a listing, and read by the three places a
/// download can start — the detail screen's button, the wall's quick sheet, and
/// the batch chooser — so all three agree on what the user is looking at.
///
/// **It replaces reading `browseQueryProvider`, and that read was the bug.**
/// A tag or an uploader opens a *pushed* `LinkedListingScreen` whose filters
/// are its own local state; the browse provider still holds whatever was last
/// typed into the search box. So downloading from a tag listing offered the
/// tag from two listings ago — "if I enter the pictures with tag flower, then
/// check the user pictures, then go to another tag like white minimalist ...
/// it just fixups on the flower tag" (the owner, 2026-08-24). A shelf that
/// publishes nothing — Favorites, the download history — now suggests nothing
/// rather than suggesting Browse's term, which was the same defect wearing a
/// different hat.
///
/// [folder] exists because a listing's query cannot always spell its own name.
/// `TagLink.narrow` sets the term to `id:37`, Wallhaven's exact-tag operator,
/// which sanitizes into a folder called `id 37`. Only the screen that followed
/// the link still holds the word, so it hands it over here.
///
/// ```dart
/// ListingOrigin(
///   filters: query,
///   folder: TagFolder.sanitize('white minimalist'),
///   child: grid,
/// );
/// ```
class ListingOrigin extends InheritedWidget {
  /// Publishes [filters] and [folder] to everything under [child].
  const ListingOrigin({
    required this.filters,
    required this.folder,
    required super.child,
    super.key,
  });

  /// The query whose results are on screen.
  final SearchQuery filters;

  /// The folder this listing names, when its own query cannot. Null for a
  /// listing whose query says everything — a Browse search — and for one that
  /// names nothing filable, such as a colour.
  final TagFolder? folder;

  /// The folder a download from [context] should be offered, or null when the
  /// surface is not a listing or the listing is not about anything nameable.
  ///
  /// Reads without subscribing: every caller asks inside a button's callback,
  /// where a dependency would only mean rebuilding an action that has already
  /// been taken.
  static TagFolder? folderOf(BuildContext context) {
    final ListingOrigin? origin = _in(context);
    if (origin == null) return null;
    return origin.folder ?? searchTagIn(origin.filters);
  }

  /// The filters of the listing [context] sits in, or null off a listing.
  static SearchQuery? filtersOf(BuildContext context) => _in(context)?.filters;

  static ListingOrigin? _in(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ListingOrigin>();

  /// Compared by value: both fields are rebuilt with the shelf around them, so
  /// an identity check would re-notify on every unrelated rebuild.
  @override
  bool updateShouldNotify(ListingOrigin oldWidget) =>
      oldWidget.filters != filters || oldWidget.folder != folder;
}
