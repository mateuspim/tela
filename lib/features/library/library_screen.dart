import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/core/ui/shelf_header.dart';
import 'package:tela/features/downloads/recent_downloads_strip.dart';
import 'package:tela/features/favorites/favorites_grid.dart';
import 'package:tela/features/favorites/favorites_providers.dart';
import 'package:tela/features/library/library_destination_tile.dart';

/// Everything kept on this device, in one place: downloads, favorites, and the
/// private library.
///
/// The tab that ended the trek through Settings to reach a download or the
/// private tier. It is a **hub of sections**, not a list of doors: the newest
/// downloads show as a preview strip you can tap straight into, because two
/// destination rows above a favorites grid left a screen and a half of black on
/// a 2560x1600 panel, which reads as broken rather than as empty (D2).
///
/// The private library keeps its plain locked row and gets no preview, which is
/// the whole point of it — a thumbnail strip on a screen with no app-lock in
/// front of it would disclose exactly what the tier exists to hide. Its
/// discretion was chosen deliberately when it lived in Settings (its old
/// `_PrivateLibraryTile` docstring argued for it) and nothing here revisits it.
class LibraryScreen extends ConsumerWidget {
  /// Creates the library hub.
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    // Watched only for the plaques' counts — each shelf loads its own copy — so
    // an unresolved local read leaves the number off for a frame rather than
    // holding the screen back.
    final int? downloads = ref.watch(recentDownloadsProvider).value?.length;
    final int? favorites = ref.watch(favoritesProvider).value?.length;
    // The hub's only selectable shelf is Favorites, so the scope wraps the
    // screen and the *Select* action rides in that shelf's own header rather
    // than the app bar — an app-bar button here would look like it selected
    // downloads and the private row too.
    return SelectionShelfScope(
      child: Scaffold(
        appBar: GradientAppBar(
          toolbarHeight: 72,
          title: Text(l10n.libraryTitle, style: text.headlineSmall),
        ),
        body: Column(
          children: <Widget>[
            ShelfHeader(
              label: l10n.libraryRecentDownloads,
              count: downloads,
              trailing: TextButton(
                onPressed: () =>
                    context.pushNamed(TelaRoutes.downloadHistoryName),
                child: Text(l10n.librarySeeAll),
              ),
            ),
            const RecentDownloadsStrip(),
            // Detached from the strip above it. Every section here is
            // delimited by its header's hairline rule, so a destination row
            // flush against the preview reads as *part of* the downloads
            // section rather than as its own door (device, 2026-07-19). It
            // stays in this position
            // because the private tier genuinely is the third download
            // destination — explicit downloads land there — and it keeps its
            // plain locked row rather than earning a plaque of its own.
            const SizedBox(height: 20),
            LibraryDestinationTile(
              icon: Icons.lock_outline,
              title: l10n.privateLibraryTitle,
              subtitle: l10n.privateLibraryOpenDetail,
              routeName: TelaRoutes.privateLibraryName,
            ),
            ShelfHeader(
              label: l10n.favoritesTitle,
              count: favorites,
              trailing: const SelectModeButton(),
            ),
            const Expanded(child: FavoritesGrid()),
          ],
        ),
      ),
    );
  }
}
