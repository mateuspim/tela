import 'package:flutter/material.dart';

/// Owns the fitted/zoomed state of a gallery transformation.
///
/// The fitted state is the identity matrix. Pinch gestures may write directly
/// to [transformationController]; this controller observes those changes so
/// viewer chrome can offer the correct accessible zoom action.
final class GalleryZoomController extends ChangeNotifier {
  /// Creates a gallery zoom controller.
  GalleryZoomController({
    TransformationController? transformationController,
    this.doubleTapScale = 2.5,
  }) : assert(doubleTapScale > 1, 'doubleTapScale must be greater than one'),
       _ownsTransformationController = transformationController == null,
       transformationController =
           transformationController ?? TransformationController() {
    _isZoomed = _readsAsZoomed();
    this.transformationController.addListener(_readTransformation);
  }

  /// The controller connected to the shared [InteractiveViewer].
  final TransformationController transformationController;

  /// The scale applied by double tap and the visible Zoom in control.
  final double doubleTapScale;

  final bool _ownsTransformationController;
  late bool _isZoomed;

  /// Whether the image has moved away from its fitted identity scale.
  bool get isZoomed => _isZoomed;

  /// Returns a transformation that keeps [focalPoint] stationary while zooming.
  Matrix4 zoomedMatrixAt(Offset focalPoint) {
    final double translationScale = 1 - doubleTapScale;
    return Matrix4.identity()
      ..translateByDouble(
        focalPoint.dx * translationScale,
        focalPoint.dy * translationScale,
        0,
        1,
      )
      ..scaleByDouble(doubleTapScale, doubleTapScale, 1, 1);
  }

  /// Immediately zooms around [focalPoint].
  void zoomAt(Offset focalPoint) {
    transformationController.value = zoomedMatrixAt(focalPoint);
  }

  /// Immediately returns the image to its fitted identity transformation.
  void reset() {
    transformationController.value = Matrix4.identity();
  }

  /// Pans a zoomed image by a small logical offset for keyboard and D-pad use.
  void panBy(Offset offset) {
    if (!isZoomed) return;
    final Matrix4 next = Matrix4.copy(transformationController.value);
    next
      ..setEntry(0, 3, next.entry(0, 3) + offset.dx)
      ..setEntry(1, 3, next.entry(1, 3) + offset.dy);
    transformationController.value = next;
  }

  bool _readsAsZoomed() {
    return transformationController.value.getMaxScaleOnAxis() > 1.001;
  }

  void _readTransformation() {
    final bool nextIsZoomed = _readsAsZoomed();
    if (nextIsZoomed == _isZoomed) return;
    _isZoomed = nextIsZoomed;
    notifyListeners();
  }

  @override
  void dispose() {
    transformationController.removeListener(_readTransformation);
    if (_ownsTransformationController) transformationController.dispose();
    super.dispose();
  }
}
