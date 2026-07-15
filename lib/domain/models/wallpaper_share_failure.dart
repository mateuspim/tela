/// Why Android could not share a wallpaper.
enum WallpaperShareProblem {
  /// The full-resolution image could not be fetched to hand to another app.
  /// Only the image path can raise this; a link needs nothing downloaded.
  source,

  /// The platform could not open a chooser — nothing on the device offered to
  /// receive the share.
  unavailable,

  /// The platform returned a failure tela does not recognize yet.
  unknown,
}

/// A safe, domain-owned wallpaper-share error.
///
/// Like `WallpaperApplyFailure`, it excludes the source URL and the vendor
/// message so neither can leak through logs or UI by accident.
class WallpaperShareFailure implements Exception {
  /// Creates a failure describing [problem].
  const WallpaperShareFailure(this.problem);

  /// The actionable category of the failure.
  final WallpaperShareProblem problem;

  @override
  String toString() => 'WallpaperShareFailure(${problem.name})';
}
