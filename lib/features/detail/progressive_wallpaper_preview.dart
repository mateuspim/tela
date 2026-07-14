import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// A zoomable preview which paints a large thumbnail while the source loads.
class ProgressiveWallpaperPreview extends StatelessWidget {
  /// Creates a progressive preview for [wallpaper].
  const ProgressiveWallpaperPreview({required this.wallpaper, super.key});

  /// Image URLs and dimensions used for the preview.
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      image: true,
      label: l10n.detailPreviewLabel(wallpaper.id),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return InteractiveViewer(
            maxScale: 4,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _image(wallpaper.thumbLargeUrl, context),
                  _image(wallpaper.fullImageUrl, context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Limits both decodes to twice the physical display width.
  Widget _image(String imageUrl, BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      memCacheWidth: _cacheWidth(context),
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => const SizedBox.expand(),
      errorWidget: (_, _, _) => const SizedBox.expand(),
    );
  }

  int _cacheWidth(BuildContext context) {
    final double physicalWidth =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    return (physicalWidth * 2).round().clamp(1, wallpaper.resolution.width);
  }
}
