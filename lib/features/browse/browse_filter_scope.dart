import 'package:tela/domain/models/search_query.dart';

/// The filters one shelf is browsing under, as the filter sheet sees them.
///
/// Two shelves offer the same sheet over different state, and the difference
/// is the point. Browse's filters are global: its tabs share them, and they are
/// what the user means by "my filters". A linked listing's are its own, so
/// narrowing a tag to People + 4K to look at that tag does not silently narrow
/// the Browse tabs waiting behind it — a pushed listing is a detour, not a new
/// home. Each answers this interface and the sheet edits whichever it was
/// given, so neither has to know the other exists.
///
/// ```dart
/// showFilterSheet(context, scope: ref.read(browseQueryProvider.notifier));
/// ```
abstract interface class BrowseFilterScope {
  /// The query being browsed now — what the sheet opens on, and what the
  /// badge counts.
  SearchQuery get filters;

  /// Replaces the whole filter set at once.
  ///
  /// One write per applied sheet: each listing costs one of Wallhaven's 45
  /// req/min, so five toggles must not cost five listings.
  void applyFilters(SearchQuery filters);

  /// Restores the filters this shelf opens on.
  ///
  /// **Purity goes back to safe here**, on both shelves. "Reset filters" is the
  /// button that undoes a sketchy or explicit session, and a shelf where it
  /// quietly did not would be worse than one with no reset at all.
  void clearFilters();
}
