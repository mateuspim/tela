import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';

/// Fills a letterboxed frame with a blurred, darkened copy of the image itself.
///
/// A 16x10 wallpaper on a 4x3 pane leaves a wide dead band above and below the
/// fitted preview. This paints that band with the wallpaper's own colours
/// instead of flat black, the way every wallpaper app does.
///
/// ```dart
/// Stack(children: <Widget>[
///   BlurredImageBackdrop(imageUrl: wallpaper.thumbOriginalUrl),
///   fittedPreview,
/// ]);
/// ```
class BlurredImageBackdrop extends StatelessWidget {
  /// Creates a blurred backdrop painted from [imageUrl].
  const BlurredImageBackdrop({
    required this.imageUrl,
    this.sigma = 28,
    this.scrimOpacity = 0.45,
    super.key,
  }) : assert(sigma > 0, 'sigma must be positive'),
       assert(
         scrimOpacity >= 0 && scrimOpacity <= 1,
         'scrimOpacity must be 0..1',
       );

  /// The image to blur. Pass a *thumbnail* URL: it is already in
  /// [thumbnailImageCache] from the shelf that led here, so this costs no
  /// fetch, and a blur destroys the detail a full-resolution decode would buy.
  final String imageUrl;

  /// Gaussian blur radius, in logical pixels.
  final double sigma;

  /// How far the backdrop is darkened towards black, so the fitted preview
  /// stays the brightest thing on the pane rather than competing with its own
  /// enlarged background.
  final double scrimOpacity;

  /// Decoded width, in device pixels.
  ///
  /// Deliberately tiny: the result is blurred and stretched across the pane, so
  /// anything larger is memory spent on detail that [sigma] then destroys.
  static const int _decodeWidthPixels = 64;

  /// Stable hook for widget tests asserting the backdrop is present.
  static const Key backdropKey = Key('blurred-image-backdrop');

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: backdropKey,
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CachedNetworkImage(
                imageUrl: imageUrl,
                cacheManager: thumbnailImageCache,
                fit: BoxFit.cover,
                memCacheWidth: _decodeWidthPixels,
                // No fade: this layer is scenery behind the real preview, and a
                // crossfade here would read as the pane flickering.
                fadeInDuration: Duration.zero,
                placeholder: (BuildContext context, String url) =>
                    const SizedBox.expand(),
                // A backdrop that cannot load is simply absent — never an
                // error glyph, which would claim the *preview* had failed.
                errorWidget: (BuildContext context, String url, Object error) =>
                    const SizedBox.expand(),
              ),
              ColoredBox(color: Colors.black.withValues(alpha: scrimOpacity)),
            ],
          ),
        ),
      ),
    );
  }
}
