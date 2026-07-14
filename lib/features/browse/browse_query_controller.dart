import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/account_defaults.dart';
import 'package:tela/domain/models/account_settings.dart';
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
/// The filters it *opens* on come from the Wallhaven account when there is one
/// — see [_adopt], which is careful about what that may overwrite.
///
/// ```dart
/// ref.read(browseQueryProvider.notifier).search('sunset');
/// ```
class BrowseQueryController extends Notifier<SearchQuery> {
  /// The filters a listing starts from, and what "Reset" resets to: tela's own
  /// until a Wallhaven account's arrive.
  SearchQuery _defaults = const SearchQuery();

  @override
  SearchQuery build() {
    ref.listen<AsyncValue<AccountSettings?>>(
      accountDefaultsProvider,
      _onAccountDefaults,
    );

    // Read rather than watch: the listener re-seeds the *filters*, where a
    // rebuild would throw away the query the user is currently browsing on.
    final SearchQuery stored = _defaultsOf(
      ref.read(accountDefaultsProvider).value,
    );
    _defaults = stored;
    return stored;
  }

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

  /// Restores the defaults: the account's if it has any, tela's otherwise.
  void clearFilters() {
    state = _withCurrentTerm(_defaults);
  }

  void _onAccountDefaults(
    AsyncValue<AccountSettings?>? previous,
    AsyncValue<AccountSettings?> next,
  ) {
    _adopt(_defaultsOf(next.value));
  }

  /// Takes [defaults] as the new base, and browses on them **only if the user
  /// has not set a filter by hand**.
  ///
  /// This is the whole "what wins" question, and the answer is: the account
  /// seeds, it does not override. Syncing on top of a filter someone just chose
  /// would silently undo their choice — but doing nothing at all would mean
  /// saving a key appears to change nothing until the next launch. "Untouched"
  /// is exactly `state == the old defaults`, which is a real comparison rather
  /// than a guess because [SearchQuery] has value equality. The search term is
  /// not a filter: searching for "sunset" does not mean you have opinions about
  /// categories.
  void _adopt(SearchQuery defaults) {
    final bool untouched = state == _withCurrentTerm(_defaults);
    _defaults = defaults;
    if (untouched) state = _withCurrentTerm(defaults);
  }

  SearchQuery _withCurrentTerm(SearchQuery query) {
    return query.copyWith(term: state.term);
  }

  /// The base query [account] asks for, or tela's own when it has none — which
  /// is also what a forgotten key leaves behind.
  SearchQuery _defaultsOf(AccountSettings? account) {
    const SearchQuery own = SearchQuery();
    return account?.applyTo(own) ?? own;
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
