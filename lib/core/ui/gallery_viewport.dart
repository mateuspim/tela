import 'package:flutter/material.dart';

/// The display-sized request a [GalleryImageSource] receives from a viewport.
@immutable
class GalleryImageRequest {
  /// Creates a request for an image fitted inside a viewport.
  const GalleryImageRequest({
    required this.logicalSize,
    required this.devicePixelRatio,
  });

  /// The exact logical size of the contained image frame.
  final Size logicalSize;

  /// The display density used to choose bounded decode dimensions.
  final double devicePixelRatio;
}

/// Supplies pixels to [GalleryViewport] without owning its zoom or geometry.
abstract interface class GalleryImageSource {
  /// Builds pixels constrained to [request]'s aspect-ratio-correct frame.
  Widget build(BuildContext context, GalleryImageRequest request);
}

/// A reusable, zoomable image canvas that never crops its source by default.
///
/// The viewport computes one contained frame from [aspectRatio]. Every loading
/// and final image supplied by [source] occupies that same frame, so a
/// progressive preview cannot expose a differently cropped composition around
/// the final image.
class GalleryViewport extends StatelessWidget {
  /// Creates a contained gallery viewport.
  const GalleryViewport({
    required this.aspectRatio,
    required this.semanticsLabel,
    required this.source,
    this.transformationController,
    this.onInteractionStart,
    this.onTap,
    this.onDoubleTapDown,
    this.onDoubleTap,
    this.heroTag,
    this.backdrop,
    this.backgroundColor = Colors.black,
    this.maxScale = 4,
    super.key,
  }) : assert(aspectRatio > 0, 'aspectRatio must be positive'),
       assert(maxScale >= 1, 'maxScale must include the fitted scale');

  /// The uncropped source width divided by its height.
  final double aspectRatio;

  /// The screen-reader description for the image.
  final String semanticsLabel;

  /// The pixels rendered inside the aspect-ratio-correct frame.
  final GalleryImageSource source;

  /// Optional zoom controller, exposed for viewer chrome and reset controls.
  final TransformationController? transformationController;

  /// Called when a pinch or pan begins, allowing viewer chrome to stop an
  /// in-flight programmatic zoom transition.
  final GestureScaleStartCallback? onInteractionStart;

  /// Called for a single tap on the image canvas.
  final GestureTapCallback? onTap;

  /// Records the focal point used by [onDoubleTap].
  final GestureTapDownCallback? onDoubleTapDown;

  /// Called for a double tap on the image canvas.
  final GestureTapCallback? onDoubleTap;

  /// Optional shared-element tag flying the originating shelf tile into this
  /// contained image. Only the image frame flies — never the zoom viewport or
  /// the calm backdrop — so the flight stays spatially coherent. Null leaves
  /// the viewport heroless, as when it is reached without a tile.
  final Object? heroTag;

  /// Optional scenery filling the letterbox around the contained image.
  ///
  /// Painted over [backgroundColor] and *under* the zoom viewport, so pinching
  /// the image never drags its own background with it. Null leaves the calm
  /// flat canvas, which is what an immersive viewer and the crop editor want:
  /// there, the frame's true bounds are the thing being judged.
  final Widget? backdrop;

  /// The calm canvas shown around an image that does not fill both axes.
  final Color backgroundColor;

  /// The largest pinch-zoom scale allowed by the viewport.
  final double maxScale;

  /// Stable hook for geometry regression tests.
  static const Key imageFrameKey = Key('gallery-viewport-image-frame');

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ColoredBox(
        color: backgroundColor,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size viewportSize = constraints.biggest;
            final Size imageSize = containedImageSize(
              viewportSize: viewportSize,
              aspectRatio: aspectRatio,
            );
            final GalleryImageRequest request = GalleryImageRequest(
              logicalSize: imageSize,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            );
            final Widget canvas = SizedBox.fromSize(
              size: viewportSize,
              child: Center(
                child: _framedImage(
                  SizedBox.fromSize(
                    key: imageFrameKey,
                    size: imageSize,
                    child: source.build(context, request),
                  ),
                ),
              ),
            );
            return _behindBackdrop(
              InteractiveViewer(
                transformationController: transformationController,
                onInteractionStart: onInteractionStart,
                minScale: 1,
                maxScale: maxScale,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: onTap,
                  onDoubleTapDown: onDoubleTapDown,
                  onDoubleTap: onDoubleTap,
                  child: canvas,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Stacks [backdrop] beneath the zoom viewport, when one was supplied.
  Widget _behindBackdrop(Widget viewer) {
    final Widget? scenery = backdrop;
    if (scenery == null) return viewer;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[scenery, viewer],
    );
  }

  /// Wraps the contained image in a [Hero] when a shelf supplied [heroTag].
  Widget _framedImage(Widget frame) {
    final Object? tag = heroTag;
    if (tag == null) return frame;
    return Hero(
      tag: tag,
      flightShuttleBuilder: _flyTileThumbnail,
      child: frame,
    );
  }

  /// Flies the grid tile's already-decoded thumbnail, in both directions, so
  /// the flight is never a blank box while this viewport's image still decodes.
  Widget _flyTileThumbnail(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final BuildContext tileContext = direction == HeroFlightDirection.push
        ? fromHeroContext
        : toHeroContext;
    return (tileContext.widget as Hero).child;
  }
}

/// Returns the largest uncropped [aspectRatio] frame inside [viewportSize].
Size containedImageSize({
  required Size viewportSize,
  required double aspectRatio,
}) {
  if (!aspectRatio.isFinite || aspectRatio <= 0) {
    throw ArgumentError.value(aspectRatio, 'aspectRatio', 'must be positive');
  }
  if (viewportSize.isEmpty) return Size.zero;

  final double viewportRatio = viewportSize.width / viewportSize.height;
  if (aspectRatio >= viewportRatio) {
    return Size(viewportSize.width, viewportSize.width / aspectRatio);
  }
  return Size(viewportSize.height * aspectRatio, viewportSize.height);
}
