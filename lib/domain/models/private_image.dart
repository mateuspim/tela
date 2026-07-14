import 'package:meta/meta.dart';

/// One image sitting in the app-private tier, as the private library sees it.
///
/// [location] is a local path to a file that may be explicit. CLAUDE.md forbids
/// logging NSFW paths, so [toString] deliberately omits it — printing one of
/// these must not be the thing that leaks it into a crash report.
@immutable
class PrivateImage {
  /// Creates a listing entry for one app-private file.
  const PrivateImage({
    required this.id,
    required this.location,
    required this.savedAt,
    required this.sizeBytes,
  });

  /// Wallhaven's id, recovered from the file name.
  final String id;

  /// Local file URI. Never log this.
  final Uri location;

  /// When the file was written.
  final DateTime savedAt;

  /// Size of the file on disk.
  final int sizeBytes;

  @override
  bool operator ==(Object other) => other is PrivateImage && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Names the image without naming where it lives.
  @override
  String toString() => 'PrivateImage($id, $sizeBytes bytes)';
}
