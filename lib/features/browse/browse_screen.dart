import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/browse_search_field.dart';
import 'package:tela/features/browse/filter_sheet.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';

/// The app's home: four listings of Wallhaven, one per tab.
///
/// Each tab is the same [WallpaperGrid] under a different [Sorting] — the tabs
/// are a query difference, not four screens. The search term and the filters
/// live in [browseQueryProvider] and are shared by all four; only `sorting` and
/// `atLeast` are layered on here, because neither is a filter the user picked.
class BrowseScreen extends ConsumerWidget {
  /// Creates the browse screen.
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SearchQuery base = ref
        .watch(browseQueryProvider)
        .copyWith(atLeast: _screenSize(context));

    return DefaultTabController(
      length: _sortings.length,
      child: Scaffold(
        appBar: AppBar(
          title: const BrowseSearchField(),
          actions: <Widget>[
            _filterButton(context, l10n),
            _favoritesButton(context, l10n),
            _settingsButton(context, l10n),
          ],
          bottom: TabBar(tabs: _tabs(l10n)),
        ),
        body: TabBarView(
          children: <Widget>[
            for (final Sorting sorting in _sortings)
              WallpaperGrid(query: base.copyWith(sorting: sorting)),
          ],
        ),
      ),
    );
  }

  Widget _filterButton(BuildContext context, AppLocalizations l10n) {
    return IconButton(
      icon: const Icon(Icons.tune),
      tooltip: l10n.browseFilters,
      onPressed: () => showFilterSheet(context),
    );
  }

  Widget _favoritesButton(BuildContext context, AppLocalizations l10n) {
    return IconButton(
      icon: const Icon(Icons.favorite_border),
      tooltip: l10n.favoritesOpen,
      onPressed: () => context.pushNamed(TelaRoutes.favoritesName),
    );
  }

  Widget _settingsButton(BuildContext context, AppLocalizations l10n) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: l10n.settingsOpen,
      onPressed: () => context.pushNamed(TelaRoutes.settingsName),
    );
  }

  /// Asks Wallhaven for images at least as large as this screen.
  ///
  /// Without it the grid fills with 1280x720 images that look soft the moment
  /// they're set as a wallpaper on a 1440p phone.
  Resolution _screenSize(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    return Resolution(
      (size.width * ratio).round(),
      (size.height * ratio).round(),
    );
  }

  List<Widget> _tabs(AppLocalizations l10n) {
    return <Widget>[
      Tab(text: l10n.browseTabLatest),
      Tab(text: l10n.browseTabTop),
      Tab(text: l10n.browseTabHot),
      Tab(text: l10n.browseTabRandom),
    ];
  }

  /// Tab order, matched positionally to [_tabs].
  static const List<Sorting> _sortings = <Sorting>[
    Sorting.dateAdded,
    Sorting.toplist,
    Sorting.hot,
    Sorting.random,
  ];
}
