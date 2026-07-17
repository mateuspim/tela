import 'package:meta/meta.dart';

/// A rectangular sub-region of a source image, in the image's own pixel space.
///
/// The output of tela's crop editor: the part of a full-resolution wallpaper
/// the user framed. It maps to Android's `Rect(left, top, right, bottom)` for
/// `BitmapRegionDecoder.decodeRegion`, so callers keep the four values in
/// source pixels, never in screen or widget coordinates.
///
/// ```dart
/// const CropRegion(left: 0, top: 240, width: 1080, height: 1920);
/// ```
@immutable
class CropRegion {
  /// Creates a region; the offset must be non-negative and the size positive.
  const CropRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(left >= 0, 'left must be >= 0'),
       assert(top >= 0, 'top must be >= 0'),
       assert(width > 0, 'width must be > 0'),
       assert(height > 0, 'height must be > 0');

  /// Distance in pixels from the source image's left edge.
  final int left;

  /// Distance in pixels from the source image's top edge.
  final int top;

  /// Width of the region in pixels.
  final int width;

  /// Height of the region in pixels.
  final int height;

  /// The exclusive right edge (`left + width`) Android's `Rect` wants.
  int get right => left + width;

  /// The exclusive bottom edge (`top + height`) Android's `Rect` wants.
  int get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is CropRegion &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'CropRegion($left, $top, ${width}x$height)';
}
