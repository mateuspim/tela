import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/gallery_zoom_animator.dart';
import 'package:tela/core/ui/gallery_zoom_controller.dart';

/// The gradual half of gallery zoom, extracted from the immersive viewer so
/// Detail could have double-tap zoom without a second copy of it.
///
/// [GalleryZoomController] can only jump; everything here is about the frames
/// in between, and about who wins when fingers or a page turn arrive during
/// them.
void main() {
  testWidgets('a toggle animates to the zoomed scale and settles there', (
    WidgetTester tester,
  ) async {
    final GalleryZoomController zoom = _zoom();
    _animator(zoom).toggleZoomAt(const Offset(100, 100), animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    final double midway = _scale(zoom);
    expect(midway, greaterThan(1), reason: 'moving by the halfway frame');
    expect(midway, lessThan(zoom.doubleTapScale), reason: 'not there yet');

    await tester.pumpAndSettle();
    expect(_scale(zoom), closeTo(zoom.doubleTapScale, 0.001));
  });

  testWidgets('a second toggle returns the image to fitted', (
    WidgetTester tester,
  ) async {
    final GalleryZoomController zoom = _zoom();
    final GalleryZoomAnimator animator = _animator(zoom)
      ..toggleZoomAt(const Offset(100, 100), animate: true);
    await tester.pumpAndSettle();
    animator.toggleZoomAt(const Offset(100, 100), animate: true);
    await tester.pumpAndSettle();

    expect(zoom.isZoomed, isFalse);
    expect(_scale(zoom), closeTo(1, 0.001));
  });

  testWidgets('the tapped point is what the zoom grows around', (
    WidgetTester tester,
  ) async {
    // The focal point arrives in one callback and is spent in another; if the
    // first is dropped the image zooms around the origin instead of the thumb.
    final GalleryZoomController zoom = _zoom();
    _animator(zoom)
      ..rememberDoubleTap(_tapAt(const Offset(120, 80)))
      ..toggleDoubleTapZoom(animate: false);

    expect(
      zoom.transformationController.value,
      zoom.zoomedMatrixAt(const Offset(120, 80)),
    );
  });

  testWidgets('animations off lands on the target in one frame', (
    WidgetTester tester,
  ) async {
    final GalleryZoomController zoom = _zoom();
    final GalleryZoomAnimator animator = _animator(zoom)
      ..toggleZoomAt(Offset.zero, animate: false);

    expect(_scale(zoom), closeTo(zoom.doubleTapScale, 0.001));
    expect(animator.isAnimating, isFalse);
  });

  testWidgets('fingers on the glass abandon the transition where it stands', (
    WidgetTester tester,
  ) async {
    // A pinch and a tween writing the same matrix would fight frame by frame.
    // The fingers win, and the image stays where the transition had reached.
    final GalleryZoomController zoom = _zoom();
    final GalleryZoomAnimator animator = _animator(zoom)
      ..toggleZoomAt(const Offset(100, 100), animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final double interrupted = _scale(zoom);

    animator.stopForInteraction(ScaleStartDetails());
    await tester.pump(const Duration(milliseconds: 200));

    expect(animator.isAnimating, isFalse);
    expect(_scale(zoom), interrupted);
  });

  testWidgets('retargeting drops the old transition and drives the new zoom', (
    WidgetTester tester,
  ) async {
    // The immersive viewer can be handed a different session's controller
    // mid-life. Finishing the old transition would write frames into a
    // controller nothing on screen is reading.
    final GalleryZoomController first = _zoom();
    final GalleryZoomController second = _zoom();
    final GalleryZoomAnimator animator = _animator(first)
      ..toggleZoomAt(const Offset(100, 100), animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final Matrix4 abandoned = first.transformationController.value;

    animator
      ..retarget(second)
      ..toggleZoomAt(const Offset(100, 100), animate: true);
    await tester.pumpAndSettle();

    expect(first.transformationController.value, abandoned);
    expect(_scale(second), closeTo(second.doubleTapScale, 0.001));
  });
}

TapDownDetails _tapAt(Offset position) =>
    TapDownDetails(localPosition: position, globalPosition: position);

double _scale(GalleryZoomController zoom) =>
    zoom.transformationController.value.getMaxScaleOnAxis();

GalleryZoomController _zoom() {
  final GalleryZoomController zoom = GalleryZoomController();
  addTearDown(zoom.dispose);
  return zoom;
}

GalleryZoomAnimator _animator(GalleryZoomController zoom) {
  final GalleryZoomAnimator animator = GalleryZoomAnimator(
    vsync: const TestVSync(),
    zoom: zoom,
  );
  addTearDown(animator.dispose);
  return animator;
}
