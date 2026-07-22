import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/selectable_wallpaper_shelf.dart';
import 'package:tela/app/wallpaper_batch_actions.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/downloads/download_viewer_launch.dart';

/// The wallpapers already on this device, each one tap away from being set.
///
/// Tapping a tile now opens the immersive, local-first viewer at that exact
/// record — the same first-class fullscreen experience as Browse — with target
/// selection moved behind the viewer's Set action.
///
/// A long press now enters multi-select rather than offering to forget the one
/// row (D4). Forgetting is still here, and still confirms in the same words —
/// it is the batch action at a count of one, since "remove from history" and
/// "delete the file" are two different things and this tile looks exactly like
/// a file.
class DownloadHistoryScreen extends ConsumerWidget {
  /// Creates the download-history screen.
  const DownloadHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<DownloadRecord>> downloads = ref.watch(
      recentDownloadsProvider,
    );
    return SelectionShelfScope(
      child: Scaffold(
        appBar: GradientAppBar(
          toolbarHeight: 72,
          title: Text(
            l10n.downloadHistoryTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          actions: const <Widget>[SelectModeButton(), SizedBox(width: 8)],
        ),
        body: downloads.when(
          data: (List<DownloadRecord> recent) =>
              _grid(context, ref, l10n, recent),
          loading: () => const WallpaperGridSkeleton(),
          error: (Object error, StackTrace stackTrace) => WallpaperStatusView(
            icon: Icons.error_outline,
            message: l10n.errorUnexpected,
          ),
        ),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<DownloadRecord> recent,
  ) {
    if (recent.isEmpty) {
      return WallpaperStatusView(
        icon: Icons.download_outlined,
        message: l10n.downloadHistoryEmpty,
      );
    }
    return SelectableWallpaperShelf(
      wallpapers: <Wallpaper>[
        for (final DownloadRecord record in recent) record.wallpaper,
      ],
      // The mirror of this shelf's marks again: everything here is downloaded,
      // so re-downloading is the one batch that says nothing. Forgetting rows
      // is what this screen is *for*, and it is the only destructive batch in
      // the app — hence the confirmation `runWallpaperBatchAction` insists on.
      actions: const <WallpaperBatchAction>[
        WallpaperBatchAction.favorite,
        WallpaperBatchAction.forget,
      ],
      child: JustifiedWallpaperGrid(
        itemCount: recent.length,
        aspectRatioOf: (int index) =>
            recent[index].wallpaper.resolution.aspectRatio,
        itemBuilder: (BuildContext context, int index, double _, double _) =>
            _tile(context, ref, l10n, recent, index),
      ),
    );
  }

  /// One download, badged when its file is no longer on the device.
  ///
  /// The badge is not a warning that something is broken — the tile still works
  /// — it is the difference between "set this from the file you already have"
  /// and "re-download six megabytes first". Those are different actions and the
  /// grid should not present them identically. The badge simply does not appear
  /// while the probe is in flight, or if it fails: an unbadged tile is the
  /// status quo, and a history that will not render because a file check hung
  /// would be a worse screen than one that under-warns.
  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<DownloadRecord> recent,
    int index,
  ) {
    final DownloadRecord download = recent[index];
    final Set<String> missing =
        ref.watch(missingDownloadsProvider).value ?? const <String>{};
    final bool isMissing = missing.contains(download.wallpaper.id);
    final gestures = selectableTileGestures(
      context: context,
      wallpaperId: download.wallpaper.id,
      onOpen: () => openDownloadViewer(context, recent, index),
      // Forgetting one row is now the batch forget at a count of one — the
      // plural strings render the identical sentence there, so the wording
      // that is the feature survives intact — which frees this gesture for the
      // same "long press means select" rule the favorites shelf follows.
      longPressSelects: true,
    );
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: isMissing
          ? l10n.downloadHistoryRedownload(download.wallpaper.id)
          : l10n.downloadHistorySetAgain(download.wallpaper.id),
      // Expand, not the default loose fit: the grid hands this tile a cell of a
      // chosen width and height, and a loose Stack would let the WallpaperTile
      // fall back to its own intrinsic size and sit top-left inside the cell.
      // Invisible while cells are wall-sized, but a lone download gets a cell
      // blown up to two thirds of the viewport, where the un-expanded tile drew
      // small and adrift (the "lone history tile" anomaly). Favorites never hit
      // this because it puts the tile straight in the SizedBox, with no Stack.
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Opacity(
            opacity: isMissing ? 0.55 : 1,
            child: WallpaperTile(
              wallpaper: download.wallpaper,
              heroTag: shelfHeroTag(
                'download-history',
                download.wallpaper.id,
                index,
              ),
              onTap: gestures.onTap,
              onLongPress: gestures.onLongPress,
              // The mirror of Favorites: everything here is downloaded by
              // definition, so only the heart carries information. It also
              // keeps this shelf to one new mark beside the missing badge.
              visibleMarks: const <WallpaperMark>{WallpaperMark.favorited},
            ),
          ),
          if (isMissing)
            Positioned(top: 8, right: 8, child: _missingBadge(context, l10n)),
        ],
      ),
    );
  }

  /// Says "this one comes from Wallhaven now", in the one word a badge has.
  Widget _missingBadge(BuildContext context, AppLocalizations l10n) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.downloadHistoryFileGone,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.cloud_download_outlined,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
