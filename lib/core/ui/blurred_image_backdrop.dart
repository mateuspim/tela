import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';
import 'package:tela/core/ui/backdrop_drift_scope.dart';

/// Fills a letterboxed frame with a blurred, darkened copy of the image itself.
///
/// A 16x10 wallpaper on a 4x3 pane leaves a wide dead band above and below the
/// fitted preview. This paints that band with the wallpaper's own colours
/// instead of flat black, the way every wallpaper app does.
///
/// Under a [BackdropDriftScope] it also *drifts*: the scenery slides against
/// whatever the user is moving — the phone's fact sheet, the tablet's
/// information pane — so the picture reads as sitting in front of a deeper
/// space rather than pasted on it. Without a scope above, it is exactly the
/// still backdrop it has always been.
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

  /// How far the scenery travels at full drift, as a fraction of its own
  /// height.
  ///
  /// The same 6% `TileEntrance.lift` uses, and for the same reason: a fraction
  /// is the same gesture on a phone's letterbox and on a tablet pane, where a
  /// fixed distance would be a lurch on one and invisible on the other.
  static const double driftHeadroom = 0.06;

  /// How much larger than its frame the drifting scenery is drawn.
  ///
  /// Twice the travel on each side, not once. Half of that is the drift; the
  /// other half keeps the blur's own edge out of frame — `TileMode.decal` fades
  /// to transparent at the layer's bounds, and at full drift a merely-exact
  /// margin would let that fade cross the edge as a dark band over the black
  /// canvas beneath.
  static const double _driftingScale = 1 + 4 * driftHeadroom;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: backdropKey,
      child: ClipRect(child: _drifting(context, _scenery())),
    );
  }

  /// Slides [scenery] with the surface a [BackdropDriftScope] is publishing.
  ///
  /// Only the translation rebuilds as the value changes — the blurred image is
  /// passed through as the builder's `child`, so a drag does not re-run a
  /// `CachedNetworkImage` sixty times a second.
  ///
  /// Held still for reduce-motion, which is the one setting that names
  /// scroll-linked parallax specifically. No scope above means no drift at all,
  /// and then the tree is exactly what it was before this existed.
  Widget _drifting(BuildContext context, Widget scenery) {
    final ValueListenable<double>? drift = BackdropDriftScope.maybeOf(context);
    if (drift == null || MediaQuery.disableAnimationsOf(context)) {
      return scenery;
    }
    return ValueListenableBuilder<double>(
      valueListenable: drift,
      builder: _driftedBy,
      child: Transform.scale(scale: _driftingScale, child: scenery),
    );
  }

  /// Offsets the oversized scenery by [drift] of the frame's own height.
  ///
  /// A fractional translation rather than a measured one: the child's layout
  /// size is still the frame — [Transform.scale] paints larger without laying
  /// out larger — so this needs no `LayoutBuilder` to know how far 6% is.
  Widget _driftedBy(BuildContext context, double drift, Widget? scenery) {
    return FractionalTranslation(
      translation: Offset(0, drift.clamp(-1, 1) * driftHeadroom),
      child: scenery,
    );
  }

  /// The still backdrop: the wallpaper, blurred, darkened towards black.
  Widget _scenery() {
    return ImageFiltered(
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
    );
  }
}
