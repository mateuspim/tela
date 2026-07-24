import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/selectable_wallpaper_shelf.dart';
import 'package:tela/app/wallpaper_batch_actions.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
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
    return SelectableWallpaperShelf(
      wallpapers: saved,
      // The mirror of the marks this shelf draws, and narrowed for the same
      // reason: *Add to favorites* here cannot change anything, because every
      // tile is already favorited. Removing them, and downloading the ones you
      // have not, are the two batches that mean something on a curated shelf.
      actions: const <WallpaperBatchAction>[
        WallpaperBatchAction.download,
        WallpaperBatchAction.unfavorite,
      ],
      child: JustifiedWallpaperGrid(
        itemCount: saved.length,
        aspectRatioOf: (int index) => saved[index].resolution.aspectRatio,
        itemBuilder: (BuildContext context, int index, double _, double _) =>
            _tile(context, saved, index),
      ),
    );
  }

  Widget _tile(BuildContext context, List<Wallpaper> saved, int index) {
    final gestures = selectableTileGestures(
      context: context,
      wallpaperKey: saved[index].ref.key,
      onOpen: () => _openDetail(context, saved, index),
      // This shelf has no other use for the gesture, so it enters selection.
      longPressSelects: true,
    );
    return WallpaperTile(
      wallpaper: saved[index],
      heroTag: shelfHeroTag('favorites', saved[index].ref.key, index),
      onTap: gestures.onTap,
      onLongPress: gestures.onLongPress,
      // Every tile here is favorited, so that mark would be decoration.
      // Whether you also *downloaded* one is the open question on this
      // shelf, and it is the only mark that answers anything.
      visibleMarks: const <WallpaperMark>{WallpaperMark.downloaded},
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
          'wallpaperKey': session.selectedItem.ref.key,
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
