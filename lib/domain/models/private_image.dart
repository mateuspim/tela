import 'package:meta/meta.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

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
    required this.ref,
    required this.location,
    required this.savedAt,
    required this.sizeBytes,
    this.tag,
    this.width,
    this.height,
  });

  /// Which source issued it and under what id, recovered from the file name.
  ///
  /// A whole [WallpaperRef] rather than a bare id, because the file name is the
  /// only record this tier has: an explicit download writes no history row, so
  /// there is no table to join a source out of. It is also what lets the grid
  /// badge a private tile with the site it came from.
  final WallpaperRef ref;

  /// Local file URI. Never log this.
  final Uri location;

  /// When the file was written.
  final DateTime savedAt;

  /// Size of the file on disk.
  final int sizeBytes;

  /// The tag folder holding this image, or null for the tier root.
  ///
  /// Read off the **directory**, exactly as [ref] is read off the file name and
  /// for the same reason: this tier keeps no rows, deliberately, so the layout
  /// on disk is the only record there is. That is also what makes tagging the
  /// private library safe — a table of what is in it would be the ungated,
  /// backed-up index the tier exists to prevent.
  final TagFolder? tag;

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
  bool operator ==(Object other) => other is PrivateImage && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;

  /// Names the image without naming where it lives — [location] and [tag] are
  /// both left out.
  ///
  /// The tag for the same reason as the path: it is a name the user chose for a
  /// folder of private images, so "waifus" discloses roughly what a path
  /// discloses. Printing one of these must not be the thing that leaks it into
  /// a crash report.
  @override
  String toString() => 'PrivateImage($ref, $sizeBytes bytes)';
}
