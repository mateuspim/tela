import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_gallery_session.dart';
import 'package:tela/features/favorites/favorites_providers.dart';

/// The wallpapers the user kept, read from SQLite.
///
/// Unpaged on purpose: favorites are a hand-curated shelf, not a Wallhaven
/// listing, so there is no next page to fetch and nothing here needs the
/// network — this screen works in airplane mode.
class FavoritesScreen extends ConsumerWidget {
  /// Creates the favorites screen.
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Wallpaper>> favorites = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          l10n.favoritesTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: favorites.when(
        data: (List<Wallpaper> saved) => _grid(context, l10n, saved),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => WallpaperStatusView(
          icon: Icons.error_outline,
          message: l10n.errorUnexpected,
        ),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    AppLocalizations l10n,
    List<Wallpaper> saved,
  ) {
    if (saved.isEmpty) {
      return WallpaperStatusView(
        icon: Icons.favorite_border,
        message: l10n.favoritesEmpty,
      );
    }
    return MasonryGridView.count(
      crossAxisCount: wallpaperGridColumns(context),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      padding: const EdgeInsets.all(12),
      itemCount: saved.length,
      itemBuilder: (BuildContext context, int index) => WallpaperTile(
        wallpaper: saved[index],
        onTap: () => _openDetail(context, saved, index),
      ),
    );
  }

  void _openDetail(
    BuildContext context,
    List<Wallpaper> saved,
    int selectedIndex,
  ) {
    unawaited(_pushDetail(context, saved, selectedIndex));
  }

  Future<void> _pushDetail(
    BuildContext context,
    List<Wallpaper> saved,
    int selectedIndex,
  ) async {
    final GallerySessionController<Wallpaper> session =
        createWallpaperGallerySession(
          context: context,
          identity: 'favorites',
          wallpapers: saved,
          initialIndex: selectedIndex,
        );
    try {
      await context.pushNamed<void>(
        TelaRoutes.detailName,
        pathParameters: <String, String>{
          'wallpaperId': session.selectedItem.id,
        },
        extra: session,
      );
    } finally {
      session.dispose();
    }
  }
}
