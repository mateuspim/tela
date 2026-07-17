import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:tela/domain/models/crop_region.dart';
import 'package:tela/features/detail/crop_geometry.dart';

/// Owns the pan/zoom state of the crop editor for one image against one frame.
///
/// Seeds to the image centred at [minCoverScale] — the framing the editor opens
/// on — and keeps the crop window fully covered on every change, so the region
/// handed to the decoder is always valid. The focal-anchoring maths lives in
/// the screen; this holds the state, clamps it, and reads out the [CropRegion].
final class CropController extends ChangeNotifier {
  /// Creates a controller for a source [image] framed by a [window]-sized crop.
  CropController({required this.image, required this.window})
    : assert(!image.isEmpty, 'image size must be positive'),
      assert(!window.isEmpty, 'window size must be positive') {
    reset();
  }

  /// The source image's own pixel dimensions.
  final Size image;

  /// The crop frame, in the same logical units as [offset].
  final Size window;

  /// How far a user may zoom past the fitted cover scale.
  static const double _maxZoomFactor = 6;

  late double _scale;
  late Offset _offset;

  /// Current scale, in logical pixels per source pixel.
  double get scale => _scale;

  /// Current image top-left, relative to the crop window's origin.
  Offset get offset => _offset;

  /// The fitted cover scale — the smallest the editor allows, and the scale the
  /// preview layer is decoded at so zooming is a paint-time transform, not a
  /// re-decode.
  double get minScale => minCoverScale(image, window);

  double get _minScale => minScale;

  /// Clamps [scale] to the fitted cover scale and the zoom ceiling.
  double clampScale(double scale) {
    return scale.clamp(_minScale, _minScale * _maxZoomFactor);
  }

  /// Applies a new [scale]/[offset], clamping both so the frame stays covered.
  void update({required double scale, required Offset offset}) {
    _scale = clampScale(scale);
    _offset = clampCropOffset(offset, image, window, _scale);
    notifyListeners();
  }

  /// Returns the image to its opening centred cover framing.
  void reset() {
    _scale = _minScale;
    _offset = centeredCropOffset(image, window, _scale);
    notifyListeners();
  }

  /// The source-pixel region currently under the crop window.
  CropRegion region() {
    return cropRegionFor(
      image: image,
      window: window,
      scale: _scale,
      offset: _offset,
    );
  }
}
