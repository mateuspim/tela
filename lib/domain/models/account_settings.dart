import 'package:meta/meta.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';

/// The browse defaults a Wallhaven account carries, as tela is willing to use
/// them.
///
/// Wallhaven's `/settings` also returns `resolutions` and `aspect_ratios`, and
/// this model deliberately drops both. They are set by desktop users at a
/// desktop: a synced `16x9` would fill a phone grid with landscape wallpapers,
/// and tela already derives `atLeast` from the screen it is actually running
/// on, which is better information than the account has. What is left —
/// categories, purity, toplist range — means the same thing on both.
///
/// ```dart
/// final SearchQuery browse = account.applyTo(const SearchQuery());
/// ```
@immutable
class AccountSettings {
  /// Creates the defaults. Neither filter may be empty: Wallhaven answers the
  /// `"000"` mask that would encode with a 400.
  const AccountSettings({
    required this.categories,
    required this.purity,
    required this.topRange,
  });

  /// Reads back what [storedCategories], [storedPurity] and [storedTopRange]
  /// wrote, or null when any of the three is unreadable.
  ///
  /// All-or-nothing on purpose: half an account's defaults is not a state worth
  /// having, and null simply means "use tela's own defaults".
  static AccountSettings? tryParse({
    required String storedCategories,
    required String storedPurity,
    required String storedTopRange,
  }) {
    final CategoryFilter? categories = CategoryFilter.tryFromApiBits(
      storedCategories,
    );
    final PurityFilter? purity = PurityFilter.tryFromApiBits(storedPurity);
    final TopRange? topRange = TopRange.tryFromApiValue(storedTopRange);
    if (categories == null || purity == null || topRange == null) return null;

    return AccountSettings(
      categories: categories,
      purity: purity,
      topRange: topRange,
    );
  }

  /// The content buckets the account browses by default.
  final CategoryFilter categories;

  /// The purities the account browses by default, as the account itself states
  /// them — explicit included. What browse *opens* on is [browsablePurity],
  /// which is deliberately not the same thing.
  final PurityFilter purity;

  /// The account's toplist window.
  final TopRange topRange;

  /// The account's purity, minus explicit.
  ///
  /// **Explicit never seeds a default, in any state.** Every other NSFW rule in
  /// tela fails toward safe — downloads route explicit content to app-private
  /// storage, the private library sits behind `FLAG_SECURE` and an app-lock, a
  /// corrupt stored purity reads as `nsfw` rather than `sfw` — and a grid that
  /// opens on explicit thumbnails the moment the app launches is the one place
  /// that would have run the other way. A phone is the device you unlock on a
  /// train. (Seen on hardware, 2026-07-14: an account with NSFW enabled made
  /// the front page explicit by default, which is how this rule was found.)
  ///
  /// So explicit stays something you turn on per session, in the filter sheet.
  /// Sketchy still seeds: it needs no key, and it is not that. Dropping the
  /// last purity would encode as `"000"`, so an explicit-only account falls
  /// back to safe.
  ///
  /// This also closes for free the hole `LoadAccountDefaults` used to guard by
  /// hand — an explicit default cannot outlive its key and turn browse into a
  /// 401, because it is never a default at all.
  PurityFilter get browsablePurity {
    final Set<Purity> safe = purity.purities
        .where((Purity p) => !p.requiresApiKey)
        .toSet();
    return safe.isEmpty ? PurityFilter.sfwOnly : PurityFilter(safe);
  }

  /// Returns [query] with these defaults applied, and everything else — the
  /// search term, the sorting, the screen-derived `atLeast` — untouched.
  SearchQuery applyTo(SearchQuery query) {
    return query.copyWith(
      categories: categories,
      purity: browsablePurity,
      topRange: topRange,
    );
  }

  /// Value equality over the *encoded* filters.
  ///
  /// The bit masks are the canonical form of a filter — same members in any
  /// order encode identically — so comparing them is both element-wise and free
  /// of a second hand-rolled set comparison.
  @override
  bool operator ==(Object other) {
    return other is AccountSettings &&
        other.categories.toApiBits() == categories.toApiBits() &&
        other.purity.toApiBits() == purity.toApiBits() &&
        other.topRange == topRange;
  }

  @override
  int get hashCode {
    return Object.hash(categories.toApiBits(), purity.toApiBits(), topRange);
  }
}
