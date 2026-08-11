import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';

/// Moves a [GalleryZoomController] between fitted and zoomed over time.
///
/// [GalleryZoomController] can only jump: `zoomAt` and `reset` write the matrix
/// outright, which is right for a pinch (the fingers are the animation) and
/// wrong for a double tap or a Zoom-in button, where a scale appearing in one
/// frame reads as a glitch. This owns the ticker and the tween that make those
/// two gradual, so every surface that offers them behaves the same way.
///
/// It also carries the double-tap focal point, because the two halves arrive in
/// separate callbacks — `onDoubleTapDown` knows *where*, `onDoubleTap` knows
/// *whether* — and a surface holding that field itself is the duplication this
/// class exists to remove.
///
/// Whether to animate at all is the caller's to decide: the answer is
/// `MediaQuery.disableAnimationsOf(context)`, and a `core/ui` collaborator that
/// reached for a [BuildContext] to ask would be harder to test than the two
/// widgets using it.
///
/// ```dart
/// _zoomAnimator = GalleryZoomAnimator(vsync: this, zoom: _zoom);
/// // ...
/// GalleryViewport(
///   onDoubleTapDown: _zoomAnimator.rememberDoubleTap,
///   onDoubleTap: () => _zoomAnimator.toggleDoubleTapZoom(animate: true),
/// )
/// ```
final class GalleryZoomAnimator {
  /// Creates an animator driving [zoom] from [vsync]'s ticker.
  ///
  /// The caller keeps ownership of [zoom]; this disposes only its own ticker.
  GalleryZoomAnimator({
    required TickerProvider vsync,
    required GalleryZoomController zoom,
    this.duration = const Duration(milliseconds: 180),
  }) : _zoom = zoom,
       _ticker = AnimationController(vsync: vsync, duration: duration) {
    _ticker.addListener(_applyFrame);
  }

  /// How long a full fitted↔zoomed transition takes.
  final Duration duration;

  final AnimationController _ticker;
  GalleryZoomController _zoom;
  Matrix4Tween? _tween;
  Offset _doubleTapPosition = Offset.zero;

  /// Whether a transition is currently running.
  bool get isAnimating => _ticker.isAnimating;

  /// Points the animator at [zoom] instead, abandoning any transition.
  ///
  /// For surfaces handed a zoom controller from outside, which may be given a
  /// different one mid-life. Finishing the old transition would write frames
  /// into a controller nothing is showing any more.
  void retarget(GalleryZoomController zoom) {
    stop();
    _zoom = zoom;
  }

  /// Records where a double tap landed, for the [toggleDoubleTapZoom] that
  /// follows it. Shaped as a `GestureTapDownCallback` so it can be passed
  /// straight to a viewport.
  void rememberDoubleTap(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  /// Zooms around the last remembered double tap, or back to fitted if the
  /// image is already magnified.
  void toggleDoubleTapZoom({required bool animate}) {
    toggleZoomAt(_doubleTapPosition, animate: animate);
  }

  /// Zooms around [focalPoint], or back to fitted if already magnified.
  void toggleZoomAt(Offset focalPoint, {required bool animate}) {
    final Matrix4 target = _zoom.isZoomed
        ? Matrix4.identity()
        : _zoom.zoomedMatrixAt(focalPoint);
    animateTo(target, animate: animate);
  }

  /// Runs the transition from wherever the image is now to [target].
  void animateTo(Matrix4 target, {required bool animate}) {
    stop();
    if (!animate) {
      _zoom.transformationController.value = target;
      return;
    }
    _tween = Matrix4Tween(
      begin: Matrix4.copy(_zoom.transformationController.value),
      end: target,
    );
    unawaited(_ticker.forward(from: 0));
  }

  /// Abandons an in-flight transition, leaving the image where it had reached.
  void stop() {
    _ticker.stop();
    _tween = null;
  }

  /// [stop], shaped as a viewport's `onInteractionStart`: fingers on the glass
  /// outrank a transition the app started, and a tween still writing frames
  /// would fight the pinch for the same matrix.
  void stopForInteraction(ScaleStartDetails details) => stop();

  void _applyFrame() {
    final Matrix4Tween? tween = _tween;
    if (tween == null) return;
    _zoom.transformationController.value = tween.evaluate(_ticker);
  }

  /// Releases the ticker. The zoom controller is not this object's to dispose.
  void dispose() {
    _ticker
      ..removeListener(_applyFrame)
      ..dispose();
  }
}
