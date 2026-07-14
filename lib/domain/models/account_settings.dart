import 'package:meta/meta.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/search_query.dart';

/// The browse defaults a Wallhaven account carries, as tela is willing to use
/// them — which is two of the five it sends.
///
/// **Purity is not synced, and that is the deliberate one.** Wallhaven's
/// `/settings` states the account's purity, and honouring it made tela's front
/// page open on explicit thumbnails for an account with NSFW enabled — a
/// masonry grid of them, at launch, behind no gate (seen on hardware,
/// 2026-07-14). Every other NSFW rule in tela fails toward safe: downloads
/// route explicit content to app-private storage, the private library sits
/// behind `FLAG_SECURE` and an app-lock, a corrupt stored purity reads as
/// `nsfw` rather than `sfw`. A phone is the device you unlock on a train, so
/// browse always opens on safe, and sketchy and explicit are things you turn on
/// for a session in the filter sheet. An account cannot decide that for you.
///
/// `resolutions` and `aspect_ratios` are dropped for a duller reason: they are
/// set by desktop users at a desktop, a synced `16x9` would fill a phone grid
/// with landscape wallpapers, and tela already derives `atLeast` from the
/// screen it is actually running on — better information than the account has.
///
/// What is left is categories and toplist range: the two that mean the same
/// thing on a phone as on the web, and that carry no risk when they are wrong.
///
/// Whether browse actually *opens* on them is now the user's choice, not this
/// class's: see [BrowseDefaultsSource].
///
/// ```dart
/// final BrowseDefaults defaults = account.toBrowseDefaults();
/// ```
@immutable
class AccountSettings {
  /// Creates the defaults. [categories] may not be empty: Wallhaven answers the
  /// `"000"` mask that would encode with a 400.
  const AccountSettings({required this.categories, required this.topRange});

  /// Reads back what [storedCategories] and [storedTopRange] wrote, or null
  /// when either is unreadable.
  ///
  /// All-or-nothing on purpose: half an account's defaults is not a state worth
  /// having, and null simply means "use tela's own defaults".
  static AccountSettings? tryParse({
    required String storedCategories,
    required String storedTopRange,
  }) {
    final CategoryFilter? categories = CategoryFilter.tryFromApiBits(
      storedCategories,
    );
    final TopRange? topRange = TopRange.tryFromApiValue(storedTopRange);
    if (categories == null || topRange == null) return null;

    return AccountSettings(categories: categories, topRange: topRange);
  }

  /// The content buckets the account browses by default.
  final CategoryFilter categories;

  /// The account's toplist window.
  final TopRange topRange;

  /// These defaults as the filters browse opens on.
  ///
  /// The account speaks for two of the five fields in [BrowseDefaults]; the
  /// rest keep tela's own values, because the account has no opinion tela is
  /// willing to take on them (see the class doc, and [BrowseDefaults] on
  /// purity).
  BrowseDefaults toBrowseDefaults() {
    return BrowseDefaults(categories: categories, topRange: topRange);
  }

  /// Value equality over the *encoded* filter.
  ///
  /// The bit mask is the canonical form of a category filter — same members in
  /// any order encode identically — so comparing it is both element-wise and
  /// free of a hand-rolled set comparison.
  @override
  bool operator ==(Object other) {
    return other is AccountSettings &&
        other.categories.toApiBits() == categories.toApiBits() &&
        other.topRange == topRange;
  }

  @override
  int get hashCode => Object.hash(categories.toApiBits(), topRange);
}
