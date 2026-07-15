import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';

void main() {
  test('tracks zoom and resets to the fitted identity matrix', () {
    final GalleryZoomController controller = GalleryZoomController();
    addTearDown(controller.dispose);
    const Offset focalPoint = Offset(120, 240);

    expect(controller.isZoomed, isFalse);
    controller.zoomAt(focalPoint);

    expect(controller.isZoomed, isTrue);
    final Offset transformedFocalPoint = MatrixUtils.transformPoint(
      controller.transformationController.value,
      focalPoint,
    );
    expect(transformedFocalPoint.dx, closeTo(focalPoint.dx, 0.001));
    expect(transformedFocalPoint.dy, closeTo(focalPoint.dy, 0.001));

    controller.reset();
    expect(controller.isZoomed, isFalse);
    expect(
      controller.transformationController.value,
      equals(Matrix4.identity()),
    );
  });

  test('observes pinch transformations written by InteractiveViewer', () {
    final TransformationController transformation = TransformationController();
    final GalleryZoomController controller = GalleryZoomController(
      transformationController: transformation,
    );
    addTearDown(controller.dispose);
    addTearDown(transformation.dispose);

    transformation.value = Matrix4.diagonal3Values(1.5, 1.5, 1);
    expect(controller.isZoomed, isTrue);

    transformation.value = Matrix4.identity();
    expect(controller.isZoomed, isFalse);
  });
}
