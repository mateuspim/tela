import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';

/// The app's home: four listings of Wallhaven, one per tab.
///
/// Each tab is the same [WallpaperGrid] under a different [Sorting] — the tabs
/// are a query difference, not four screens.
class BrowseScreen extends StatelessWidget {
  /// Creates the browse screen.
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SearchQuery base = _deviceSizedQuery(context);

    return DefaultTabController(
      length: _sortings.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.appTitle),
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

  /// Asks Wallhaven for images at least as large as this screen.
  ///
  /// Without it the grid fills with 1280x720 images that look soft the moment
  /// they're set as a wallpaper on a 1440p phone.
  SearchQuery _deviceSizedQuery(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    return SearchQuery(
      atLeast: Resolution(
        (size.width * ratio).round(),
        (size.height * ratio).round(),
      ),
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
