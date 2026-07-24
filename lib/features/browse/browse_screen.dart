import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/browse_filter_text.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/screen_resolution.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/features/browse/browse_filter_button.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/browse_search_field.dart';
import 'package:tela/features/browse/browse_source_button.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';

/// The app's home: one Wallhaven listing per sorting, as tabs.
///
/// Each tab is the same [WallpaperGrid] under a different [Sorting] — the tabs
/// are a query difference, not six screens. The search term and the filters
/// live in [browseQueryProvider] and are shared by all of them; `sorting` is
/// layered on here because it belongs to the tab rather than to the user's
/// filters, and `forScreen` is what answers an *Automatic* resolution filter,
/// which is the one filter only a widget can resolve.
///
/// The tab list is not fixed. Relevance appears only while a search term is set
/// (see [offerableSortings]) and is selected on submit, so the bar grows and
/// shrinks under the user — which the state below tracks by sorting rather than
/// by tab index, so that nobody is silently moved to another listing.
class BrowseScreen extends ConsumerStatefulWidget {
  /// Creates the browse screen.
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with TickerProviderStateMixin {
  /// The listing the user is on, held by *identity* and never by tab index.
  ///
  /// Relevance appearing or vanishing renumbers every tab behind it, so an
  /// index would quietly move someone from Top to Hot when they cleared a
  /// search.
  Sorting _selected = Sorting.dateAdded;

  /// The tabs [_tabs] was built for. Replaced together with it, and only when
  /// the list itself changes.
  List<Sorting> _sortings = const <Sorting>[];
  TabController? _tabs;

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    ref.listen<String>(
      browseQueryProvider.select((SearchQuery query) => query.term),
      _onTerm,
    );

    final SearchQuery query = ref.watch(browseQueryProvider);
    final WallpaperSource source = ref.watch(activeWallpaperSourceProvider);
    final SearchQuery base = query.forScreen(screenResolution(context));
    final List<Sorting> sortings = offerableSortings(
      hasTerm: base.term.isNotEmpty,
      supported: source.capabilities.sortings,
    );
    final TabController tabs = _controllerFor(sortings);

    // Above the Scaffold, so the app bar's Select action and the tiles below
    // share one selection — an InheritedWidget only reaches downwards. All the
    // sorting tabs share it too, which is harmless: ticks resolve against the
    // visible listing, so an id from another tab simply stops counting.
    return SelectionShelfScope(
      child: Scaffold(
        appBar: GradientAppBar(
          toolbarHeight: 72,
          titleSpacing: 16,
          title: const BrowseSearchField(),
          actions: <Widget>[
            const BrowseSourceButton(),
            const SelectModeButton(),
            BrowseFilterButton(
              filters: query,
              scope: ref.read(browseQueryProvider.notifier),
            ),
            const SizedBox(width: 8),
          ],
          bottom: _tabBar(l10n, tabs, sortings),
        ),
        body: TabBarView(
          controller: tabs,
          children: <Widget>[
            for (final Sorting sorting in sortings)
              // Keyed by the sorting, not by slot: Relevance appearing
              // shifts every grid one place right, and an unkeyed one would
              // inherit the paging state of the listing that used to sit there.
              WallpaperGrid(
                key: ValueKey<(SourceId, Sorting)>((source.id, sorting)),
                query: base.copyWith(sorting: sorting),
              ),
          ],
        ),
      ),
    );
  }

  /// Scrollable, because seven sortings do not fit across a phone. Fixed tabs
  /// would shrink to fit and cut their own labels off.
  TabBar _tabBar(
    AppLocalizations l10n,
    TabController tabs,
    List<Sorting> sortings,
  ) {
    return TabBar(
      controller: tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      tabs: <Widget>[
        for (final Sorting sorting in sortings)
          Tab(text: sortingLabel(l10n, sorting)),
      ],
    );
  }

  /// The controller for [sortings], rebuilt only when that list changes.
  ///
  /// It cannot simply be rebuilt every frame — that would restart the animation
  /// mid-swipe — and it cannot be kept when Relevance appears, because a
  /// [TabController] shorter than its [TabBar] throws. So it is replaced
  /// exactly when the list is, and the selected sorting carries across.
  TabController _controllerFor(List<Sorting> sortings) {
    final TabController? current = _tabs;
    if (current != null && listEquals(sortings, _sortings)) return current;

    // The listing the user was on may be the one that just vanished.
    if (!sortings.contains(_selected)) _selected = Sorting.dateAdded;
    current?.dispose();
    _sortings = sortings;
    return _tabs = TabController(
      length: sortings.length,
      initialIndex: sortings.indexOf(_selected),
      vsync: this,
    )..addListener(_recordSelection);
  }

  /// Submitting a search selects Relevance.
  ///
  /// It is the one sorting that exists *for* a term: a search that left you on
  /// Latest would rank by upload date and take no account of what you typed.
  ///
  /// Only a non-empty term is handled here. Clearing the term drops Relevance
  /// from the list, and [_controllerFor] falls back to Latest on its way past —
  /// so the emptied case needs no branch of its own.
  void _onTerm(String? previous, String next) {
    final bool supportsRelevance = ref
        .read(activeWallpaperSourceProvider)
        .capabilities
        .sortsBy(Sorting.relevance);
    if (next.isEmpty || !supportsRelevance) return;
    _selected = Sorting.relevance;

    // Refining a search that is already running: the list does not change
    // shape, so nothing rebuilds the controller and the tab must be moved by
    // hand. A first search leaves this at -1 and is carried by the rebuild.
    final int relevance = _sortings.indexOf(Sorting.relevance);
    if (relevance >= 0) _tabs?.animateTo(relevance);
  }

  /// Remembers which listing the user swiped or tapped to, so that Relevance
  /// arriving or leaving does not land them on a different one.
  void _recordSelection() {
    final TabController? tabs = _tabs;
    if (tabs == null) return;
    _selected = _sortings[tabs.index];
  }
}
