import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/blurred_image_backdrop.dart';
import 'package:tela/core/ui/gallery_viewport.dart';
import 'package:tela/core/ui/progressive_network_gallery_source.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// Adapts a Wallhaven wallpaper to tela's shared, uncropped gallery viewport.
class ProgressiveWallpaperPreview extends StatelessWidget {
  /// Creates a progressive preview for [wallpaper].
  const ProgressiveWallpaperPreview({
    required this.wallpaper,
    this.heroTag,
    this.transformationController,
    this.onInteractionStart,
    this.onDoubleTapDown,
    this.onDoubleTap,
    this.onTap,
    this.fillLetterbox = false,
    super.key,
  });

  /// Image URLs and dimensions used for the preview.
  final Wallpaper wallpaper;

  /// Optional shared-element tag flying the shelf tile into this preview.
  final Object? heroTag;

  /// Optional externally owned zoom state for this preview's pinch gestures.
  ///
  /// Null leaves the viewport's zoom private, which is all a surface needs when
  /// nothing around it has to react. Detail's pager passes one because it has
  /// to know: a pan across a magnified image must not turn the page.
  final TransformationController? transformationController;

  /// Called when a pinch or pan begins, so an owner animating the zoom can drop
  /// the transition rather than fight the fingers for the same matrix.
  final GestureScaleStartCallback? onInteractionStart;

  /// Records the focal point a following [onDoubleTap] zooms around.
  final GestureTapDownCallback? onDoubleTapDown;

  /// Called for a double tap on the image, conventionally a zoom toggle.
  ///
  /// Withheld — like [transformationController] — from the pages a pager
  /// pre-builds: an off-screen neighbour's gesture would write to zoom state
  /// belonging to the wallpaper actually on screen.
  final GestureTapCallback? onDoubleTap;

  /// Called for a single tap on the image.
  ///
  /// Detail passes the way into fullscreen, so the picture itself is the target
  /// rather than only the ⛶ in its corner. Withheld from a pager's pre-built
  /// neighbours alongside the other gestures — not because a tap there would do
  /// the wrong thing, but because a page that is not the selected one has no
  /// business being interactive.
  final GestureTapCallback? onTap;

  /// Whether to paint the letterbox with a blurred copy of the wallpaper.
  ///
  /// On for the Detail pane, whose fixed-height preview strands ~160dip of dead
  /// black around a wide wallpaper. Off everywhere the frame's real bounds are
  /// the point: the immersive viewer and the crop editor.
  final bool fillLetterbox;

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
      transformationController: transformationController,
      onInteractionStart: onInteractionStart,
      onDoubleTapDown: onDoubleTapDown,
      onDoubleTap: onDoubleTap,
      onTap: onTap,
      backdrop: fillLetterbox
          // The same thumbnail the preview and the shelf tile already fetched,
          // so the fill costs no request.
          ? BlurredImageBackdrop(imageUrl: wallpaper.thumbOriginalUrl)
          : null,
    );
  }
}
