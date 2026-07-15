import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/progressive_network_gallery_source.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// Adapts a Wallhaven wallpaper to tela's shared, uncropped gallery viewport.
class ProgressiveWallpaperPreview extends StatelessWidget {
  /// Creates a progressive preview for [wallpaper].
  const ProgressiveWallpaperPreview({
    required this.wallpaper,
    this.heroTag,
    super.key,
  });

  /// Image URLs and dimensions used for the preview.
  final Wallpaper wallpaper;

  /// Optional shared-element tag flying the shelf tile into this preview.
  final Object? heroTag;

  /// Creates the one progressive source shared by normal and immersive Detail.
  static GalleryImageSource sourceFor(Wallpaper wallpaper) {
    return ProgressiveNetworkGallerySource(
      // Wallhaven's large thumbnail may be a different crop. The original
      // thumbnail preserves the source composition used by the final image.
      previewUrl: wallpaper.thumbOriginalUrl,
      imageUrl: wallpaper.fullImageUrl,
      sourcePixelSize: Size(
        wallpaper.resolution.width.toDouble(),
        wallpaper.resolution.height.toDouble(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return GalleryViewport(
      aspectRatio: wallpaper.resolution.width / wallpaper.resolution.height,
      semanticsLabel: l10n.detailPreviewLabel(wallpaper.id),
      source: sourceFor(wallpaper),
      heroTag: heroTag,
    );
  }
}
