import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/core/ui/wallpaper_source_badge.dart';
import 'package:tela/core/ui/wallpaper_source_labels_scope.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// One wallpaper in the browse grid.
///
/// Deliberately does **not** size itself: the justified row it sits in assigns
/// every tile the row's shared height, and a tile that measured itself from its
/// own aspect ratio would fight that. The row derives its heights from the same
/// ratio, so the thumb still shows uncropped — see `justifiedRows`.
class WallpaperTile extends StatelessWidget {
  /// Creates a tile for [wallpaper].
  const WallpaperTile({
    required this.wallpaper,
    this.onTap,
    this.onLongPress,
    this.heroTag,
    this.visibleMarks = const <WallpaperMark>{
      WallpaperMark.favorited,
      WallpaperMark.downloaded,
    },
    this.showSourceBadge = false,
    super.key,
  });

  /// The wallpaper to show.
  final Wallpaper wallpaper;

  /// Called when the tile is tapped. Null renders a non-interactive tile.
  final VoidCallback? onTap;

  /// Called on a long press. Null in the browse grid, where a tile has no
  /// second action; the download history uses it to forget a row.
  final VoidCallback? onLongPress;

  /// Optional shared-element tag flying this thumbnail into the viewer it
  /// opens. Scope it by shelf identity so the same id on two shelves does not
  /// collide (see `shelfHeroTag`); null leaves the tile heroless.
  final Object? heroTag;

  /// Which "you already have this" marks this shelf is allowed to draw.
  ///
  /// Defaults to both, which is what Browse and the linked listing want. The
  /// library shelves narrow it: a heart on every tile of Favorites, or a
  /// download mark on every tile of the history, is true of the whole shelf and
  /// so tells the user nothing. Whether a tile *earns* a mark comes from
  /// [WallpaperMarksScope]; this only says which ones the shelf shows.
  final Set<WallpaperMark> visibleMarks;

  /// Whether this shelf draws the source-name badge.
  ///
  /// False on the browse wall, where every tile is the active source and a
  /// badge on all of them says nothing. The library shelves — which can hold
  /// wallpapers from more than one site at once — turn it on. Same per-shelf
  /// opt-in as [visibleMarks], and for the same "tells you nothing" reason.
  final bool showSourceBadge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      button: onTap != null,
      selected: WallpaperSelectionScope.isActive(context)
          ? WallpaperSelectionScope.isSelected(context, wallpaper.ref.key)
          : null,
      label: AppLocalizations.of(context).detailPreviewLabel(wallpaper.id),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(wallpaperTileRadius),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: _thumbnail(context),
        ),
      ),
    );
  }

  /// Decodes at roughly the on-screen width, not the source width.
  ///
  /// Uses the *original* thumb, not the small one: Wallhaven crops `small` to a
  /// fixed 300x200, so pouring it into a box shaped by the wallpaper's real
  /// aspect ratio center-punches the image (a landscape becomes a close-up).
  Widget _thumbnail(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final Widget image = CachedNetworkImage(
      imageUrl: wallpaper.thumbOriginalUrl,
      cacheManager: thumbnailImageCache,
      fit: BoxFit.cover,
      memCacheWidth: (_tileWidthDip * devicePixelRatio).round(),
      fadeInDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      placeholder: (BuildContext context, String url) =>
          const SizedBox.expand(),
      errorWidget: (BuildContext context, String url, Object error) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
    final Widget framed = Container(
      foregroundDecoration: wallpaperTileEdge(
        Theme.of(context).colorScheme,
      ),
      child: image,
    );
    final Object? tag = heroTag;
    final Widget thumb = tag == null ? framed : Hero(tag: tag, child: framed);

    final Set<WallpaperMark> marks = WallpaperMarksScope.marksFor(
      context,
      wallpaper.ref.key,
      visibleMarks,
    );
    final Widget? badge = _sourceBadge(context);
    final Widget? selection = _selectionOverlay(context);
    if (marks.isEmpty && badge == null && selection == null) return thumb;
    // Outside the Hero on purpose: a mark inside it would fly into the detail
    // screen along with the thumbnail and land on top of the full preview. The
    // source badge and selection tick are outside for the same reason, and the
    // tick additionally because a tick flying into a screen that has no
    // selection mode is nonsense.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        thumb,
        if (marks.isNotEmpty)
          Positioned(bottom: 6, right: 6, child: _marks(context, marks)),
        ?badge,
        ?selection,
      ],
    );
  }

  /// The tick and the wash, or null when this shelf is not selecting.
  ///
  /// Drawn on *every* tile while selection runs, not only the ticked ones: an
  /// empty circle on the untouched tiles is what says the whole shelf has
  /// changed mode, and without it the first tap on an unticked tile looks like
  /// it should open the wallpaper.
  ///
  /// Top-left is this overlay's corner — the download history owns top-right
  /// for its missing badge, C4's marks own bottom-right, and the source badge
  /// owns bottom-left — so the four never collide on a history tile that is
  /// missing, marked, badged and ticked at once.
  Widget? _selectionOverlay(BuildContext context) {
    if (!WallpaperSelectionScope.isActive(context)) return null;
    return WallpaperSelectionOverlay(wallpaperKey: wallpaper.ref.key);
  }

  /// The source-name pill in the free bottom-left corner, or null when this
  /// shelf does not show it or the source's name is not in scope.
  ///
  /// The name is resolved through [WallpaperSourceLabelsScope] — one root-level
  /// watch of the registry — rather than a per-tile provider lookup, the same
  /// way the marks avoid a family watch on a wall of hundreds.
  Widget? _sourceBadge(BuildContext context) {
    if (!showSourceBadge) return null;
    final String? name = WallpaperSourceLabelsScope.labelFor(
      context,
      wallpaper.ref.source.value,
    );
    if (name == null) return null;
    return Positioned(
      bottom: 6,
      left: 6,
      child: WallpaperSourceBadge(sourceName: name),
    );
  }

  /// The marks as one pill, in the corner the missing badge leaves free.
  ///
  /// That badge is top-right and means something else entirely ("this file is
  /// gone, a tap costs a re-download"), so these sit bottom-right rather than
  /// competing with it. One shared pill rather than a badge per mark keeps a
  /// doubly-marked tile from growing two pieces of chrome.
  Widget _marks(BuildContext context, Set<WallpaperMark> marks) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String> said = <String>[
      if (marks.contains(WallpaperMark.favorited)) l10n.wallpaperMarkFavorited,
      if (marks.contains(WallpaperMark.downloaded))
        l10n.wallpaperMarkDownloaded,
    ];
    return Semantics(
      label: said.join(', '),
      child: Tooltip(
        message: said.join(' · '),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Opaque enough to stay legible over a wallpaper of any luminance —
            // the same problem `wallpaperTileEdge` solves for the tile border.
            color: colors.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: <Widget>[
                if (marks.contains(WallpaperMark.favorited))
                  Icon(Icons.favorite, size: 14, color: colors.primary),
                if (marks.contains(WallpaperMark.downloaded))
                  Icon(
                    Icons.download_done,
                    size: 14,
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Half a phone's logical width, matching the 2-column grid.
  static const double _tileWidthDip = 200;
}
