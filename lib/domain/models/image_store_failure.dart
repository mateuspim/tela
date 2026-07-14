/// A safe reason an image download could not be stored.
enum ImageStoreProblem {
  /// The remote image could not be downloaded.
  source,

  /// The requested destination cannot be used on this device.
  unavailable,

  /// A shared non-gallery directory still needs the user's selection.
  notConfigured,

  /// The destination would violate the image's privacy restrictions.
  restricted,

  /// An unexpected platform failure occurred.
  unknown,
}

/// Operational failure from an image-storage adapter.
///
/// It deliberately contains no source URL or local path, both of which could
/// expose a private download through a surfaced exception.
class ImageStoreFailure implements Exception {
  /// Creates a failure with a safe, user-displayable category.
  const ImageStoreFailure(this.problem);

  /// The non-sensitive reason the image was not saved.
  final ImageStoreProblem problem;

  @override
  String toString() => 'ImageStoreFailure(${problem.name})';
}
