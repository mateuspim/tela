import 'package:flutter/material.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/features/favorites/favorites_grid.dart';
import 'package:tela/features/library/library_destination_tile.dart';

/// Everything kept on this device, in one place: favorites, download history,
/// and the private library.
///
/// The tab that ended the trek through Settings to reach a download or the
/// private tier. The two other stores sit as entries above the favorites grid —
/// always in reach, never buried — while the private one stays a plain, locked
/// row rather than a thumbnailed shortcut, keeping the discretion the Settings
/// placement was chosen for (its `_PrivateLibraryTile` said as much).
class LibraryScreen extends StatelessWidget {
  /// Creates the library hub.
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(l10n.libraryTitle, style: text.headlineSmall),
      ),
      body: Column(
        children: <Widget>[
          LibraryDestinationTile(
            icon: Icons.history_outlined,
            title: l10n.downloadHistoryTitle,
            subtitle: l10n.downloadHistoryOpenDetail,
            routeName: TelaRoutes.downloadHistoryName,
          ),
          LibraryDestinationTile(
            icon: Icons.lock_outline,
            title: l10n.privateLibraryTitle,
            subtitle: l10n.privateLibraryOpenDetail,
            routeName: TelaRoutes.privateLibraryName,
          ),
          const Divider(height: 1),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(l10n.favoritesTitle, style: text.titleSmall),
            ),
          ),
          const Expanded(child: FavoritesGrid()),
        ],
      ),
    );
  }
}
