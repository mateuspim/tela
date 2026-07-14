import 'package:meta/meta.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

/// Where the filters a listing opens on come from.
///
/// The user picks, in Settings. This replaces the heuristic that used to answer
/// the question — the account's defaults were adopted only while the current
/// query still equalled the old ones, which worked but was invisible: you could
/// not see it, predict it, or overrule it. A switch you can see is worth more
/// than a rule that is clever.
///
/// ```dart
/// await settings.setBrowseDefaultsSource(BrowseDefaultsSource.device);
/// ```
enum BrowseDefaultsSource {
  /// The Wallhaven account's own browse settings, as last synced.
  ///
  /// The default, and what every build before the switch did: it keeps a device
  /// that upgrades browsing exactly as it did yesterday.
  account,

  /// A snapshot of the filters saved from this device's filter sheet.
  device;

  /// Reads back what [name] wrote, or null for a value no build ever stored.
  ///
  /// Fail-soft on purpose, unlike a bare `values.byName`: an unreadable row
  /// should cost the *setting* and fall back to [account], not throw and cost
  /// the app a browse screen.
  static BrowseDefaultsSource? tryFromName(String name) {
    return BrowseDefaultsSource.values
        .where((BrowseDefaultsSource source) => source.name == name)
        .firstOrNull;
  }
}

/// The defaults in force, and which source they came from.
///
/// Browse needs both, and not out of curiosity: it treats the two kinds of
/// change differently. A changed [source] is a deliberate act in Settings, so
/// it resets the listing outright. Changed [defaults] from the *same* source is
/// the backfill or a manual refresh landing, which must not silently undo a
/// filter the user set by hand while it was in flight.
@immutable
class ActiveBrowseDefaults {
  /// Creates the pair.
  const ActiveBrowseDefaults({required this.source, required this.defaults});

  /// Where [defaults] came from.
  final BrowseDefaultsSource source;

  /// The filters browse opens on.
  final BrowseDefaults defaults;

  @override
  bool operator ==(Object other) {
    return other is ActiveBrowseDefaults &&
        other.source == source &&
        other.defaults == defaults;
  }

  @override
  int get hashCode => Object.hash(source, defaults);
}

/// The filters a fresh listing starts from, and what "Reset" returns to.
///
/// **Purity is not one of them, and it is absent rather than ignored.** Browse
/// always opens on safe. Wallhaven's `/settings` states an account's purity,
/// and honouring it turned tela's front page into a masonry grid of explicit
/// thumbnails, at launch, behind no gate (seen on hardware, 2026-07-14). The
/// same argument outlives the account: a *saved* default carrying explicit
/// would do the identical thing, just with the user's own fingerprints on it,
/// and a phone is the device you unlock on a train. Sketchy and explicit stay
/// per-session choices in the filter sheet, which is the one place they are
/// always a deliberate act. A field nothing reads is a field somebody
/// eventually applies, so there is no field.
///
/// `sorting` is absent for a duller reason: it belongs to the tab you are on,
/// not to the filters you chose. So is `atLeast`, which comes from the screen
/// tela is actually running on.
///
/// ```dart
/// final SearchQuery browse = defaults.applyTo(const SearchQuery());
/// ```
@immutable
class BrowseDefaults {
  /// Creates the defaults. Every field defaults to tela's own, so
  /// `const BrowseDefaults()` *is* the fallback the app browses on before any
  /// account is synced and before any snapshot is saved.
  const BrowseDefaults({
    this.categories = CategoryFilter.all,
    this.topRange = TopRange.oneMonth,
    this.ratios = const <RatioChoice>[ExactRatio(9, 16)],
    this.order = SortOrder.desc,
    this.color,
  });

  /// Captures the filters [query] currently expresses.
  ///
  /// This is "save what I am looking at as my default". The term is not a
  /// filter — searching for "sunset" is not an opinion about categories — and
  /// the purity is not saved at all, per the class doc.
  factory BrowseDefaults.of(SearchQuery query) {
    return BrowseDefaults(
      categories: query.categories,
      topRange: query.topRange,
      ratios: query.ratios,
      order: query.order,
      color: query.color,
    );
  }

  /// Reads back what a [BrowseDefaults] was stored as, or null when any part of
  /// it is unreadable.
  ///
  /// All-or-nothing, like `AccountSettings.tryParse`: half a saved snapshot is
  /// not a state worth having, and null means "fall back to tela's own", which
  /// is somewhere the app is always happy to browse.
  static BrowseDefaults? tryParse({
    required String storedCategories,
    required String storedTopRange,
    required String storedRatios,
    required String storedOrder,
    String? storedColor,
  }) {
    final CategoryFilter? categories = CategoryFilter.tryFromApiBits(
      storedCategories,
    );
    final TopRange? topRange = TopRange.tryFromApiValue(storedTopRange);
    final SortOrder? order = SortOrder.values
        .where((SortOrder value) => value.name == storedOrder)
        .firstOrNull;
    if (categories == null || topRange == null || order == null) return null;

    return BrowseDefaults(
      categories: categories,
      topRange: topRange,
      // An empty stored list is "any shape", which is a real choice — not a
      // missing one — so it must not decay into tela's portrait default.
      ratios: RatioChoice.readAll(storedRatios),
      order: order,
      // One unreadable swatch costs the colour, not the snapshot: the filter is
      // still a filter without it, and "any colour" is a legitimate state.
      color: storedColor == null
          ? null
          : WallpaperColor.readAll(<String>[storedColor]).firstOrNull,
    );
  }

  /// The content buckets a listing opens on.
  final CategoryFilter categories;

  /// The toplist window, for the tabs that use one.
  final TopRange topRange;

  /// Aspect ratios to accept, as a union. Empty means no ratio filter at all.
  final List<RatioChoice> ratios;

  /// Direction of the tab's sorting.
  final SortOrder order;

  /// Dominant colour to match, or null for any colour.
  final WallpaperColor? color;

  /// The stored form of [ratios]: a comma-joined list, empty for "any shape".
  String encodedRatios() => RatioChoice.encode(ratios) ?? '';

  /// Returns [query] with these defaults applied, and everything they do not
  /// speak for — the purity, the term, the tab's sorting, the screen-derived
  /// `atLeast` — left exactly as it was.
  ///
  /// Goes through [SearchQuery.withColor] rather than `copyWith` because a
  /// snapshot saved with *no* colour has to be able to clear one: `copyWith`
  /// reads a null colour as "leave it alone", which would make an adopted
  /// default unable to turn the filter off.
  SearchQuery applyTo(SearchQuery query) {
    return query
        .copyWith(
          categories: categories,
          topRange: topRange,
          ratios: ratios,
          order: order,
        )
        .withColor(color);
  }

  /// Value equality over the encoded filter, element-wise where it must be.
  ///
  /// Load-bearing rather than tidy: browse compares the defaults it is holding
  /// against the ones that just arrived to decide whether to adopt them, and
  /// `==` on a `List` is identity.
  @override
  bool operator ==(Object other) {
    return other is BrowseDefaults &&
        other.categories.toApiBits() == categories.toApiBits() &&
        other.topRange == topRange &&
        other.encodedRatios() == encodedRatios() &&
        other.order == order &&
        other.color == color;
  }

  @override
  int get hashCode {
    return Object.hash(
      categories.toApiBits(),
      topRange,
      encodedRatios(),
      order,
      color,
    );
  }
}
