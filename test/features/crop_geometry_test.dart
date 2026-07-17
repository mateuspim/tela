import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/crop_region.dart';
import 'package:tela/features/detail/crop_geometry.dart';

void main() {
  group('minCoverScale', () {
    test('takes the axis that binds — a tall frame on a wide image', () {
      // 1920/1000 = 1.92 dwarfs 1080/2000 = 0.54, so height binds.
      expect(
        minCoverScale(const Size(2000, 1000), const Size(1080, 1920)),
        closeTo(1.92, 1e-9),
      );
    });

    test('is 1.0 when frame and image are the same size', () {
      expect(
        minCoverScale(const Size(500, 500), const Size(500, 500)),
        1.0,
      );
    });
  });

  group('clampCropOffset', () {
    test('holds each axis inside [window - scale*image, 0]', () {
      // scale 1.0 on a 1000-square image gives a range of [-500, 0].
      final Offset clamped = clampCropOffset(
        const Offset(100, -600),
        const Size(1000, 1000),
        const Size(500, 500),
        1,
      );
      expect(clamped, const Offset(0, -500));
    });
  });

  group('centeredCropOffset', () {
    test('centres the over-wide image behind the frame', () {
      expect(
        centeredCropOffset(
          const Size(2000, 1000),
          const Size(1080, 1920),
          1.92,
        ),
        const Offset(-1380, 0),
      );
    });
  });

  group('cropRegionFor', () {
    test('a square frame on a square image at cover scale takes it whole', () {
      final CropRegion region = cropRegionFor(
        image: const Size(1000, 1000),
        window: const Size(500, 500),
        scale: 0.5,
        offset: Offset.zero,
      );
      expect(
        region,
        const CropRegion(left: 0, top: 0, width: 1000, height: 1000),
      );
    });

    test('zooming 2x past cover keeps the centred half', () {
      final CropRegion region = cropRegionFor(
        image: const Size(1000, 1000),
        window: const Size(500, 500),
        scale: 1,
        offset: const Offset(-250, -250),
      );
      expect(
        region,
        const CropRegion(left: 250, top: 250, width: 500, height: 500),
      );
    });

    test('maps the panned wide-image sub-rect to source pixels', () {
      final CropRegion region = cropRegionFor(
        image: const Size(2000, 1000),
        window: const Size(1080, 1920),
        scale: 1.92,
        offset: const Offset(-1380, 0),
      );
      expect(
        region,
        const CropRegion(left: 719, top: 0, width: 562, height: 1000),
      );
    });

    test('clamps a region that would overhang the image bounds', () {
      final CropRegion region = cropRegionFor(
        image: const Size(1000, 1000),
        window: const Size(500, 500),
        scale: 0.5,
        offset: const Offset(1000, 1000),
      );
      expect(region.left, 0);
      expect(region.top, 0);
      expect(region.right, lessThanOrEqualTo(1000));
      expect(region.bottom, lessThanOrEqualTo(1000));
    });
  });
}
