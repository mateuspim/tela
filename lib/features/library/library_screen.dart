import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/shelf_header.dart';
import 'package:tela/features/favorites/favorites_grid.dart';
import 'package:tela/features/favorites/favorites_providers.dart';
import 'package:tela/features/library/library_destination_tile.dart';

/// Everything kept on this device, in one place: favorites, download history,
/// and the private library.
///
/// The tab that ended the trek through Settings to reach a download or the
/// private tier. The two other stores sit as entries above the favorites grid —
/// always in reach, never buried — while the private one stays a plain, locked
/// row rather than a thumbnailed shortcut, keeping the discretion the Settings
/// placement was chosen for (its `_PrivateLibraryTile` said as much).
class LibraryScreen extends ConsumerWidget {
  /// Creates the library hub.
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    // Watched only for the plaque's count; the grid loads its own copy. Null
    // until the local read returns, which leaves the count off for one frame.
    final int? count = ref.watch(favoritesProvider).value?.length;
    return Scaffold(
      appBar: GradientAppBar(
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
          ShelfHeader(label: l10n.favoritesTitle, count: count),
          const Expanded(child: FavoritesGrid()),
        ],
      ),
    );
  }
}
