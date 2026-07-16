import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// One wallpaper in the browse grid.
///
/// Sized to the image's own aspect ratio so a masonry grid can pack portrait
/// and landscape thumbs without letterboxing either.
class WallpaperTile extends StatelessWidget {
  /// Creates a tile for [wallpaper].
  const WallpaperTile({
    required this.wallpaper,
    this.onTap,
    this.onLongPress,
    this.heroTag,
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

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      button: onTap != null,
      label: AppLocalizations.of(context).detailPreviewLabel(wallpaper.id),
      child: AspectRatio(
        aspectRatio: wallpaper.resolution.width / wallpaper.resolution.height,
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
    final Object? tag = heroTag;
    if (tag == null) return image;
    return Hero(tag: tag, child: image);
  }

  /// Half a phone's logical width, matching the 2-column grid.
  static const double _tileWidthDip = 200;
}
