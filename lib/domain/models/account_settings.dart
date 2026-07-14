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

  /// The purities the account browses by default. May include NSFW — the
  /// account has a key by definition, but *this device* only has one while a
  /// key is stored, hence [withoutExplicit].
  final PurityFilter purity;

  /// The account's toplist window.
  final TopRange topRange;

  /// Returns [query] with these defaults applied, and everything else — the
  /// search term, the sorting, the screen-derived `atLeast` — untouched.
  SearchQuery applyTo(SearchQuery query) {
    return query.copyWith(
      categories: categories,
      purity: purity,
      topRange: topRange,
    );
  }

  /// Returns these defaults with explicit content removed.
  ///
  /// What an account asks for and what a keyless device may *request* are two
  /// different things: an NSFW search with no key is a 401, so browse would
  /// open on an error rather than a grid. Dropping the last purity would encode
  /// as `"000"`, so an explicit-only account falls back to safe.
  AccountSettings withoutExplicit() {
    final Set<Purity> safe = purity.purities
        .where((Purity p) => !p.requiresApiKey)
        .toSet();
    if (safe.length == purity.purities.length) return this;

    return AccountSettings(
      categories: categories,
      purity: safe.isEmpty ? PurityFilter.sfwOnly : PurityFilter(safe),
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
