import 'package:meta/meta.dart';
import 'package:tela/domain/models/source_id.dart';

/// Where one collection lives — which source, whose account, which list.
///
/// Three parts because a collection id is only unique *within* an account: two
/// users' "Default" lists are different collections on the same source, and
/// Wallhaven's contents endpoint is addressed as
/// `/collections/{owner}/{id}` rather than by id alone.
///
/// [id] is a `String` even though Wallhaven issues integers, for the same
/// reason [SourceId] is open: the next source to grow collections may key them
/// by slug, and widening a stored `int` later would orphan every row written
/// before the change.
///
/// ```dart
/// const CollectionRef(
///   source: SourceId.wallhaven,
///   owner: 'jrmnt',
///   id: '1797738',
/// );
/// ```
@immutable
class CollectionRef {
  /// Addresses one collection on one source.
  const CollectionRef({
    required this.source,
    required this.owner,
    required this.id,
  });

  /// The site the collection lives on.
  final SourceId source;

  /// The account that owns it, as the source spells the username.
  final String owner;

  /// The source-native collection id.
  final String id;

  /// A stable key for a paging shelf or a route — `wallhaven:jrmnt:1797738`.
  String get key => '${source.value}:$owner:$id';

  @override
  bool operator ==(Object other) =>
      other is CollectionRef &&
      other.source == source &&
      other.owner == owner &&
      other.id == id;

  @override
  int get hashCode => Object.hash(source, owner, id);

  @override
  String toString() => key;
}

/// One named list of wallpapers somebody assembled on a source.
///
/// The listing *row*, not its contents: [count] is what the source says the
/// whole list holds, and fetching a page of it is a separate request that may
/// legitimately answer with far fewer.
///
/// **[count] and a fetched page's `total` are different numbers, and the gap is
/// the point.** Measured live against Wallhaven on 2026-08-26: collection
/// `jrmnt/1651328` reports `count: 82`, and its contents under the default
/// purity answer `total: 0` — every wallpaper in it is sketchy or explicit.
/// Under `purity=111` with no API key it answers 22, because the explicit ones
/// are dropped silently rather than refused. So [count] is the honest size of
/// the list and a page's total is the size of *what this user may see of it*;
/// a screen that shows only the latter renders an empty grid under a row that
/// promised 82, with nothing to explain the difference.
///
/// ```dart
/// final int hidden = collection.count - (page.total ?? collection.count);
/// ```
@immutable
class WallpaperCollection {
  /// Creates a collection row.
  const WallpaperCollection({
    required this.ref,
    required this.label,
    required this.count,
    required this.isPublic,
    this.views,
  });

  /// Which collection this is.
  final CollectionRef ref;

  /// The name its owner gave it — "Default", "Interiors".
  ///
  /// Not localized and never translated: it is a user's own words, the same
  /// way `WallpaperSource.displayName` is a brand.
  final String label;

  /// How many wallpapers the source says it holds, before any purity filter.
  ///
  /// See the class docstring: this is not what a page of contents will
  /// necessarily return.
  final int count;

  /// Whether the source publishes it to people other than its owner.
  ///
  /// Kept even though the private ones only ever arrive on an authenticated
  /// listing, because that is exactly where the distinction has to be drawn on
  /// screen: a user looking at their own collections needs to know which of
  /// them strangers can read.
  final bool isPublic;

  /// View count, where the source publishes one. Null is "not counted", never
  /// zero-by-assumption.
  final int? views;

  @override
  bool operator ==(Object other) =>
      other is WallpaperCollection &&
      other.ref == ref &&
      other.label == label &&
      other.count == count &&
      other.isPublic == isPublic &&
      other.views == views;

  @override
  int get hashCode => Object.hash(ref, label, count, isPublic, views);
}
