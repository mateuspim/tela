import 'package:meta/meta.dart';

/// A downsampled preview of one vault image, decoded once by the native side
/// and cached there by location.
///
/// Unlike a `LocalPreview`, this is never released: it lives under the
/// platform's own cache directory, keyed by the source location, so a grid
/// tile scrolled past and back finds it already there instead of paying for a
/// second decode. It carries the source's real pixel bounds alongside the
/// preview path, which is the whole reason it exists — see
/// `LocalPreviewCache.materializeThumbnail`.
///
/// ```dart
/// final thumb = await cache.materializeThumbnail(location, 400);
/// if (thumb != null) Image.file(File(thumb.path));
/// ```
@immutable
class VaultThumbnail {
  /// Creates a thumbnail pointing at a readable local [path].
  const VaultThumbnail({
    required this.path,
    required this.width,
    required this.height,
  });

  /// An absolute filesystem path a `FileImage` can decode.
  final String path;

  /// The source image's real pixel width, from before it was downsampled.
  final int width;

  /// The source image's real pixel height, from before it was downsampled.
  final int height;

  /// The source's width over its height — for laying out a grid tile.
  double get aspectRatio => width / height;

  @override
  bool operator ==(Object other) =>
      other is VaultThumbnail &&
      other.path == path &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(path, width, height);

  @override
  String toString() => 'VaultThumbnail(${width}x$height)';
}
