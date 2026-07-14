import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// One wallpaper in the browse grid.
///
/// Sized to the image's own aspect ratio so a masonry grid can pack portrait
/// and landscape thumbs without letterboxing either.
class WallpaperTile extends StatelessWidget {
  /// Creates a tile for [wallpaper].
  const WallpaperTile({required this.wallpaper, this.onTap, super.key});

  /// The wallpaper to show.
  final Wallpaper wallpaper;

  /// Called when the tile is tapped. Null renders a non-interactive tile.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: wallpaper.resolution.width / wallpaper.resolution.height,
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
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
    return CachedNetworkImage(
      imageUrl: wallpaper.thumbOriginalUrl,
      fit: BoxFit.cover,
      memCacheWidth: (_tileWidthDip * devicePixelRatio).round(),
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (BuildContext context, String url) =>
          const SizedBox.expand(),
      errorWidget: (BuildContext context, String url, Object error) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }

  /// Half a phone's logical width, matching the 2-column grid.
  static const double _tileWidthDip = 200;
}
