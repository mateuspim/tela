import 'package:meta/meta.dart';

/// Pixel dimensions of an image, and the source of the `atleast` search filter.
///
/// ```dart
/// const Resolution(1080, 2400).toApiValue(); // '1080x2400'
/// ```
@immutable
class Resolution {
  /// Creates a resolution; both dimensions must be positive.
  const Resolution(this.width, this.height)
    : assert(width > 0, 'width must be > 0'),
      assert(height > 0, 'height must be > 0');

  /// Parses Wallhaven's `"1920x1080"` form.
  ///
  /// ```dart
  /// Resolution.parse('1920x1080'); // Resolution(1920, 1080)
  /// ```
  factory Resolution.parse(String raw) {
    final Resolution? parsed = Resolution.tryParse(raw);
    if (parsed == null) {
      throw ArgumentError(
        'resolution must be "<width>x<height>" with positive integers, '
        'got "$raw"',
      );
    }
    return parsed;
  }

  /// The resolution [raw] names, or null when it names none.
  ///
  /// Beside the throwing [Resolution.parse], and for the same reason
  /// `Purity.tryFromApiName` sits beside `Purity.fromApiName`: a wallpaper
  /// whose size tela cannot read is a bug worth throwing on, while a *stored*
  /// filter that has gone bad should cost the filter and not the screen it sits
  /// on.
  ///
  /// ```dart
  /// Resolution.tryParse('nonsense'); // null
  /// ```
  static Resolution? tryParse(String raw) {
    final List<String> parts = raw.split('x');
    if (parts.length != 2) return null;

    final int? width = int.tryParse(parts[0]);
    final int? height = int.tryParse(parts[1]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Resolution(width, height);
  }

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Encodes to the form Wallhaven's `atleast` param expects.
  String toApiValue() => '${width}x$height';

  /// True when the image is taller than it is wide — the phone-shaped ones.
  bool get isPortrait => height > width;

  @override
  bool operator ==(Object other) =>
      other is Resolution && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => toApiValue();
}
