import 'package:meta/meta.dart';

/// One image sitting in the app-private tier, as the private library sees it.
///
/// [location] is a local path to a file that may be explicit. CLAUDE.md forbids
/// logging NSFW paths, so [toString] deliberately omits it — printing one of
/// these must not be the thing that leaks it into a crash report.
@immutable
class PrivateImage {
  /// Creates a listing entry for one app-private file.
  ///
  /// [width] and [height] are the file's pixel dimensions from a bounds-only
  /// decode, and are null when the file could not be decoded — a corrupt or
  /// truncated download the gallery must still render as a safe broken state.
  const PrivateImage({
    required this.id,
    required this.location,
    required this.savedAt,
    required this.sizeBytes,
    this.width,
    this.height,
  });

  /// Wallhaven's id, recovered from the file name.
  final String id;

  /// Local file URI. Never log this.
  final Uri location;

  /// When the file was written.
  final DateTime savedAt;

  /// Size of the file on disk.
  final int sizeBytes;

  /// Pixel width from a bounds-only decode, or null when it could not decode.
  final int? width;

  /// Pixel height from a bounds-only decode, or null when it could not decode.
  final int? height;

  /// The file's width over its height, or null when either is unknown.
  ///
  /// Null for a corrupt file whose bounds could not be read: the tile falls
  /// back to a square, and the viewer to a neutral square canvas, both showing
  /// a safe broken-image state rather than dividing by an unknown dimension.
  double? get aspectRatio {
    final int? w = width;
    final int? h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  @override
  bool operator ==(Object other) => other is PrivateImage && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Names the image without naming where it lives.
  @override
  String toString() => 'PrivateImage($id, $sizeBytes bytes)';
}
