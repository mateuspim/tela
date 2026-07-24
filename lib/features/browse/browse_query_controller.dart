import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/browse_defaults.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/features/browse/browse_filter_scope.dart';

/// The listing the browse tabs are currently showing.
final NotifierProvider<BrowseQueryController, SearchQuery> browseQueryProvider =
    NotifierProvider<BrowseQueryController, SearchQuery>(
      BrowseQueryController.new,
    );

/// The search term and filters, as one [SearchQuery] every tab shares.
///
/// One field of the query is deliberately *not* held here, because it is not
/// a filter the user chose: `sorting` belongs to the tab you are on. The browse
/// screen layers it on before handing the query to a grid, and it also calls
/// `forScreen` — which fills in the device's own size for a resolution filter
/// left on *Automatic*, the one choice the domain cannot answer for itself.
///
/// The filters it *opens* on come from [browseDefaultsProvider] — the Wallhaven
/// account's, or this device's saved snapshot, whichever the user picked in
/// Settings. See `_onDefaults` for what a change to that may overwrite.
///
/// ```dart
/// ref.read(browseQueryProvider.notifier).search('sunset');
/// ```
class BrowseQueryController extends Notifier<SearchQuery>
    implements BrowseFilterScope {
  /// The filters a listing starts from, and what "Reset" resets to.
  BrowseDefaults _defaults = const BrowseDefaults();

  /// The source [_defaults] came from, so a *change* of source can be told
  /// apart from the same source answering differently.
  BrowseDefaultsSource? _source;

  @override
  SearchQuery build() {
    ref
      ..listen<AsyncValue<ActiveBrowseDefaults>>(
        browseDefaultsProvider,
        _onDefaults,
      )
      ..listen<AsyncValue<SourceId>>(activeSourceProvider, _onSourceChanged);

    // Read rather than watch: the listener re-seeds the *filters*, where a
    // rebuild would throw away the query the user is currently browsing on.
    final ActiveBrowseDefaults? active = ref.read(browseDefaultsProvider).value;
    _source = active?.source;
    _defaults = active?.defaults ?? const BrowseDefaults();
    return _defaults.applyTo(const SearchQuery());
  }

  @override
  SearchQuery get filters => state;

  /// The query a shelf opens on with nothing set by hand — what "Reset" means.
  ///
  /// Onto a *fresh* query rather than the current one, which is what puts the
  /// purity back to safe. A linked listing resets to this same place: its
  /// filters are its own, but "no filters" is not a per-shelf opinion.
  SearchQuery get defaultQuery => _defaults.applyTo(const SearchQuery());

  /// Sets the free-text term. Empty means "browse", not "search for nothing".
  void search(String term) {
    state = state.copyWith(term: term.trim());
  }

  /// Replaces the whole filter set at once.
  ///
  /// The filter sheet edits a draft and applies it here in one write: each
  /// applied query costs one of the 45 req/min, so five toggles must not cost
  /// five listings.
  @override
  void applyFilters(SearchQuery filters) {
    state = filters.copyWith(term: state.term);
  }

  /// Restores the defaults browse currently opens on.
  ///
  /// The one place the purity goes back to safe — "Reset filters" is the button
  /// that undoes a sketchy or explicit session. The term survives: it is not a
  /// filter.
  @override
  void clearFilters() {
    state = defaultQuery.copyWith(term: state.term);
  }

  /// Resets the listing when the *site* changes.
  ///
  /// Filters are not portable between sources: one site's tags, categories and
  /// sortings mean nothing on another, and carrying them across would silently
  /// drop the halves the new source cannot honour. The term goes too — it was
  /// typed against a different index.
  ///
  /// Only a change between two *known* ids counts. The first resolution of the
  /// stored setting arrives as loading → data, and treating that as a switch
  /// would wipe filters the user set before the read landed.
  void _onSourceChanged(
    AsyncValue<SourceId>? previous,
    AsyncValue<SourceId> next,
  ) {
    final SourceId? before = previous?.value;
    final SourceId? after = next.value;
    if (before == null || after == null || before == after) return;
    state = defaultQuery;
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

/// The purities the active source can serve with the credentials on hand.
///
/// Wallhaven withholds explicit until a key exists; Konachan serves all three
/// anonymously. Both decisions come from [capabilities], never a site name.
List<Purity> offerablePurities({
  required SourceCapabilities capabilities,
  required bool hasApiKey,
}) {
  return <Purity>[
    for (final Purity purity in Purity.values)
      if (capabilities.purities.contains(purity) &&
          (purity != Purity.nsfw ||
              hasApiKey ||
              capabilities.credentials == SourceCredentials.none))
        purity,
  ];
}

/// The sortings the browse tabs may offer: Relevance only with a search term.
///
/// Not a matter of taste either — `relevance` ranks results *against* `q`, so
/// with no term there is nothing to rank against and Wallhaven answers with an
/// arbitrary listing. A tab that silently means something else is worse than a
/// tab that isn't there.
///
/// Relevance leads, because it is the sorting a search wants and is selected on
/// submit; the six that stand on their own follow, in the order they were
/// always in.
///
/// ```dart
/// offerableSortings(hasTerm: false); // no Sorting.relevance
/// ```
List<Sorting> offerableSortings({
  required bool hasTerm,
  required Set<Sorting> supported,
}) {
  return <Sorting>[
    if (hasTerm && supported.contains(Sorting.relevance)) Sorting.relevance,
    for (final Sorting sorting in _termlessSortings)
      if (supported.contains(sorting)) sorting,
  ];
}

/// The sortings that mean something with no search term behind them.
const List<Sorting> _termlessSortings = <Sorting>[
  Sorting.dateAdded,
  Sorting.toplist,
  Sorting.hot,
  Sorting.random,
  Sorting.views,
  Sorting.favorites,
];
