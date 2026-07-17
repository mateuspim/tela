import 'dart:ui';

import 'package:tela/domain/models/crop_region.dart';

// The pan/zoom maths behind the crop editor, kept pure so it can be pinned by
// unit tests without pumping a widget.
//
// The model: a source image `image` (its own pixels) is drawn at `scale`
// logical-pixels-per-image-pixel, its top-left at `offset` in the crop window's
// coordinate space (window top-left is the origin). So a window point `(x, y)`
// reveals source pixel `((x - offset.dx) / scale, …)`.

/// The smallest scale at which `image` fully covers a `window`-sized frame.
///
/// Below it, one axis of the frame would show past the image edge — which a
/// wallpaper crop must never do. It is the lower bound the controller clamps.
double minCoverScale(Size image, Size window) {
  return _maxOf(window.width / image.width, window.height / image.height);
}

/// Clamps [offset] so the image still covers the whole `window` at [scale].
///
/// Each axis is bounded to `[window - scale*image, 0]`: the near edge cannot
/// pass the window's origin, and the far edge cannot fall short. The lower
/// bound is `<= 0` at or above [minCoverScale], the controller's own invariant.
Offset clampCropOffset(
  Offset offset,
  Size image,
  Size window,
  double scale,
) {
  final double minX = window.width - scale * image.width;
  final double minY = window.height - scale * image.height;
  return Offset(
    offset.dx.clamp(minX, 0),
    offset.dy.clamp(minY, 0),
  );
}

/// The centered [Offset] for [scale] — the framing the editor opens on.
Offset centeredCropOffset(Size image, Size window, double scale) {
  return Offset(
    (window.width - scale * image.width) / 2,
    (window.height - scale * image.height) / 2,
  );
}

/// The source-pixel [CropRegion] under a `window`-sized frame at [scale]/[offset].
///
/// Inverts the display transform for the frame's four corners, rounds to whole
/// pixels, and clamps inside the image — so a sub-pixel overhang from a clamped
/// pan can never hand the decoder an out-of-bounds rect.
CropRegion cropRegionFor({
  required Size image,
  required Size window,
  required double scale,
  required Offset offset,
}) {
  final int iw = image.width.round();
  final int ih = image.height.round();
  final int left = _clampInt((-offset.dx / scale).round(), 0, iw);
  final int top = _clampInt((-offset.dy / scale).round(), 0, ih);
  final int right = _clampInt(
    ((window.width - offset.dx) / scale).round(),
    left + 1,
    iw,
  );
  final int bottom = _clampInt(
    ((window.height - offset.dy) / scale).round(),
    top + 1,
    ih,
  );
  return CropRegion(
    left: left,
    top: top,
    width: right - left,
    height: bottom - top,
  );
}

int _clampInt(int value, int lower, int upper) {
  if (value < lower) return lower;
  if (value > upper) return upper;
  return value;
}

double _maxOf(double a, double b) => a > b ? a : b;
