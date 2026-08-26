import 'package:meta/meta.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';

/// One filter a source may or may not be able to honour.
///
/// The filter sheet renders *from* this set rather than showing everything and
/// hoping. The failure mode being designed out is the obvious alternative:
/// accepting a filter the source cannot honour and silently dropping it, which
/// looks to the user like the app ignoring them.
enum SourceFilter {
  /// The general/anime/people axis. Wallhaven has it; a booru has no such
  /// notion at all.
  categories,

  /// Which purities to include.
  purity,

  /// Dominant colour. Needs the source to publish colour data per wallpaper.
  colors,

  /// Aspect ratio.
  ratios,

  /// A minimum or exact pixel size.
  resolutions,

  /// Tags demanded or forbidden by name.
  tags,

  /// Ascending or descending result order.
  order,

  /// The look-back window of a toplist sorting.
  topRange,
}

/// Whether a source needs credentials, and what they buy.
enum SourceCredentials {
  /// Nothing to store. Konachan serves explicit content anonymously —
  /// verified live, 2026-07-24 — so refusing an NSFW query for want of a key
  /// would refuse a request the source would happily answer.
  none,

  /// A key unlocks explicit content. Wallhaven: SFW works without one, `nsfw`
  /// purity is a 401 without it.
  nsfwRequiresKey,
}

/// What one source can actually do, as the app is allowed to ask it.
///
/// Declared by each adapter and read by the UI and the search use case, so
/// neither has to know which site is active. Adding a source is one adapter
/// and one registry entry; no feature file learns its name.
///
/// ```dart
/// if (capabilities.supports(SourceFilter.colors)) showPalette();
/// ```
@immutable
class SourceCapabilities {
  /// Declares what a source supports. Everything is explicit: a new capability
  /// with a default would silently claim something of every existing adapter.
  const SourceCapabilities({
    required this.filters,
    required this.sortings,
    required this.purities,
    required this.credentials,
    required this.requestsPerMinute,
    required this.syncsAccountDefaults,
    required this.browsesCollections,
  });

  /// The filter groups the source can honour.
  final Set<SourceFilter> filters;

  /// The orderings it can serve. Konachan has no relevance, toplist or hot,
  /// and its `order:random` takes no seed — so paging it repeats images, and
  /// it is declared unsupported rather than shipped as a sort that quietly
  /// duplicates (PLAN §18.3).
  final Set<Sorting> sortings;

  /// The purities it can serve at all.
  final Set<Purity> purities;

  /// What it wants stored, and what that unlocks.
  final SourceCredentials credentials;

  /// The client-side request ceiling, per minute. Wallhaven publishes 45;
  /// Konachan publishes nothing and sits behind Cloudflare, so its adapter
  /// picks a conservative number of its own.
  final int requestsPerMinute;

  /// Whether the source can hand back the account's own browse defaults —
  /// Wallhaven's `/settings`. A source without an account has none to sync.
  final bool syncsAccountDefaults;

  /// Whether the source publishes user-assembled collections to browse.
  ///
  /// Gates `WallpaperSource.collectionsOf` and
  /// `WallpaperSource.collectionPage` the same way [syncsAccountDefaults]
  /// gates `accountSettings()`: a source without collections throws
  /// `UnsupportedError` from both, and reaching them without asking here first
  /// is a programming error rather than a runtime one.
  final bool browsesCollections;

  /// Whether [filter] is one this source can honour.
  bool supports(SourceFilter filter) => filters.contains(filter);

  /// Whether [sorting] is one this source can serve.
  bool sortsBy(Sorting sorting) => sortings.contains(sorting);

  /// Whether asking for [purity] requires a stored key this source has not got.
  ///
  /// The question `SearchWallpapers` asks before spending a request on a
  /// guaranteed 401 — and the reason it asks *the source* rather than
  /// assuming: on a keyless source the same query is perfectly servable.
  bool needsKeyFor(PurityFilter purity) =>
      credentials == SourceCredentials.nsfwRequiresKey &&
      purity.purities.contains(Purity.nsfw);
}
