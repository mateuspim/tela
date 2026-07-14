import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/browse_defaults.dart';
import 'package:tela/domain/models/browse_defaults.dart';
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
/// The filters it *opens* on come from [browseDefaultsProvider] — the Wallhaven
/// account's, or this device's saved snapshot, whichever the user picked in
/// Settings. See `_onDefaults` for what a change to that may overwrite.
///
/// ```dart
/// ref.read(browseQueryProvider.notifier).search('sunset');
/// ```
class BrowseQueryController extends Notifier<SearchQuery> {
  /// The filters a listing starts from, and what "Reset" resets to.
  BrowseDefaults _defaults = const BrowseDefaults();

  /// The source [_defaults] came from, so a *change* of source can be told
  /// apart from the same source answering differently.
  BrowseDefaultsSource? _source;

  @override
  SearchQuery build() {
    ref.listen<AsyncValue<ActiveBrowseDefaults>>(
      browseDefaultsProvider,
      _onDefaults,
    );

    // Read rather than watch: the listener re-seeds the *filters*, where a
    // rebuild would throw away the query the user is currently browsing on.
    final ActiveBrowseDefaults? active = ref.read(browseDefaultsProvider).value;
    _source = active?.source;
    _defaults = active?.defaults ?? const BrowseDefaults();
    return _defaults.applyTo(const SearchQuery());
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

  /// Restores the defaults browse currently opens on.
  ///
  /// Onto a *fresh* query, so this is also the one place the purity goes back
  /// to safe — "Reset filters" is the button that undoes a sketchy or explicit
  /// session. The term survives: it is not a filter.
  void clearFilters() {
    state = _defaults.applyTo(const SearchQuery()).copyWith(term: state.term);
  }

  void _onDefaults(
    AsyncValue<ActiveBrowseDefaults>? previous,
    AsyncValue<ActiveBrowseDefaults> next,
  ) {
    final ActiveBrowseDefaults? active = next.value;
    if (active == null) return;

    // A changed source is the user standing in Settings saying "take my
    // defaults from *there* now". Nothing about the listing they left behind
    // outranks that, so it is adopted outright — including over filters they
    // set by hand, which is the whole point of having asked.
    final bool switched = _source != null && _source != active.source;
    _source = active.source;
    _adopt(active.defaults, outright: switched);
  }

  /// Takes [defaults] as the new base, and browses on them — **only if the user
  /// has not set a filter by hand**, unless [outright].
  ///
  /// The guarded case is defaults arriving *late* from the source already in
  /// force: the account backfill, or a manual refresh. Landing those on top of
  /// a filter someone just chose would silently undo it — but doing nothing at
  /// all would mean saving a key appears to change nothing until the next
  /// launch. "Untouched" is a real comparison rather than a guess:
  /// [BrowseDefaults] has value equality, so the live query's own filters
  /// either still encode the old defaults or they do not.
  ///
  /// Applied onto the **current** query, not a fresh one, so what the defaults
  /// do not speak for survives: the term, the tab's sorting, and — the
  /// load-bearing one — the purity. Adopting a snapshot must not quietly switch
  /// the grid back to safe under someone who turned sketchy on for this
  /// session. Purity only goes back to safe on a relaunch or an explicit
  /// [clearFilters].
  void _adopt(BrowseDefaults defaults, {required bool outright}) {
    final bool untouched = BrowseDefaults.of(state) == _defaults;
    _defaults = defaults;
    if (outright || untouched) state = defaults.applyTo(state);
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
