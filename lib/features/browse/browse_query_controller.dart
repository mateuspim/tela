import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';

/// The listing the browse tabs are currently showing.
final NotifierProvider<BrowseQueryController, SearchQuery> browseQueryProvider =
    NotifierProvider<BrowseQueryController, SearchQuery>(
      BrowseQueryController.new,
    );

/// The search term and filters, as one [SearchQuery] every tab shares.
///
/// Two fields of the query are deliberately *not* held here, because they are
/// not the user's filter choice: `sorting` belongs to the tab you are on, and
/// `atLeast` comes from the screen you are holding. The browse screen layers
/// both on top of this state before handing the query to a grid.
///
/// ```dart
/// ref.read(browseQueryProvider.notifier).search('sunset');
/// ```
class BrowseQueryController extends Notifier<SearchQuery> {
  @override
  SearchQuery build() => const SearchQuery();

  /// Sets the free-text term. Empty means "browse", not "search for nothing".
  void search(String term) {
    state = state.copyWith(term: term.trim());
  }

  /// Replaces the whole filter set at once.
  ///
  /// The filter sheet edits a draft and applies it here in one write: each
  /// applied query costs one of the 45 req/min, so five toggles must not cost
  /// five listings.
  void applyFilters(SearchQuery filters) {
    state = filters.copyWith(term: state.term);
  }

  /// Restores the browse defaults: safe content, every category, portrait.
  void clearFilters() {
    state = SearchQuery(term: state.term);
  }
}

/// The aspect ratios a listing asks for, as the three choices worth offering on
/// a phone.
///
/// Wallhaven takes an open-ended ratio list, but "portrait / landscape / any" is
/// the only cut of it a wallpaper app needs. Named for the ratios it sets, not
/// `Orientation`, which is already a Flutter enum.
enum RatioChoice {
  /// Phone-shaped. The default, because this is a phone.
  portrait(<String>['9x16']),

  /// Desktop-shaped, for downloading to sync elsewhere.
  landscape(<String>['16x9']),

  /// No ratio filter at all.
  any(<String>[]);

  const RatioChoice(this.ratios);

  /// The `ratios` param value this choice stands for.
  final List<String> ratios;

  /// The choice [query] currently expresses.
  ///
  /// Falls back to [any] for a ratio set we never offered: nothing in the app
  /// builds one today, but [SearchQuery] permits it and this must not throw.
  static RatioChoice of(SearchQuery query) {
    return RatioChoice.values.firstWhere(
      (RatioChoice choice) => _sameRatios(choice.ratios, query.ratios),
      orElse: () => RatioChoice.any,
    );
  }

  static bool _sameRatios(List<String> a, List<String> b) {
    return a.length == b.length && a.toSet().containsAll(b);
  }
}

/// Returns [selected] with [value] toggled, refusing to empty the set.
///
/// Both of Wallhaven's bit masks throw on `'000'`, so "nothing selected" is not
/// a state the filter sheet is allowed to reach — the last chip stays on.
Set<T> toggledChoice<T>(Set<T> selected, T value) {
  if (!selected.contains(value)) return <T>{...selected, value};
  if (selected.length == 1) return selected;
  return <T>{...selected}..remove(value);
}

/// The purities the filter sheet may offer: NSFW only once a key is stored.
///
/// Not a matter of taste — Wallhaven answers an NSFW listing with 401 when no
/// key is sent, so an offered chip would simply fail.
List<Purity> offerablePurities({required bool hasApiKey}) {
  if (hasApiKey) return Purity.values;
  return <Purity>[Purity.sfw, Purity.sketchy];
}
