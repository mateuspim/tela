import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_detail_args.dart';
import 'package:tela/features/detail/wallpaper_gallery_session.dart';
import 'package:tela/features/favorites/favorites_providers.dart';

/// The wallpapers the user kept, read from SQLite, as an embeddable grid.
///
/// Unpaged on purpose: favorites are a hand-curated shelf, not a Wallhaven
/// listing, so there is no next page to fetch and nothing here needs the
/// network — this works in airplane mode. It carries no app bar of its own, so
/// the Library screen sits it beneath the shelves reaching the other tiers.
class FavoritesGrid extends ConsumerWidget {
  /// Creates the favorites grid.
  const FavoritesGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Wallpaper>> favorites = ref.watch(favoritesProvider);

    return favorites.when(
      data: (List<Wallpaper> saved) => _grid(context, l10n, saved),
      loading: () => const WallpaperGridSkeleton(),
      error: (Object error, StackTrace stackTrace) => WallpaperStatusView(
        icon: Icons.error_outline,
        message: l10n.errorUnexpected,
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
    return JustifiedWallpaperGrid(
      itemCount: saved.length,
      aspectRatioOf: (int index) => saved[index].resolution.aspectRatio,
      itemBuilder: (BuildContext context, int index, double _, double _) =>
          WallpaperTile(
            wallpaper: saved[index],
            heroTag: shelfHeroTag('favorites', saved[index].id, index),
            onTap: () => _openDetail(context, saved, index),
            // Every tile here is favorited, so that mark would be decoration.
            // Whether you also *downloaded* one is the open question on this
            // shelf, and it is the only mark that answers anything.
            visibleMarks: const <WallpaperMark>{WallpaperMark.downloaded},
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
        // No origin filters: a curated shelf has no browse query to inherit, so
        // a tag followed from here falls back to Browse's own (see B1).
        extra: WallpaperDetailArgs(session: session),
      );
    } finally {
      session.dispose();
    }
  }
}
