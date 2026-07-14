/// Why Android could not apply a wallpaper.
enum WallpaperApplyProblem {
  /// The full-resolution image could not be downloaded or read.
  source,

  /// This device does not support the requested target.
  unsupported,

  /// Android or the device manufacturer rejected the operation.
  rejected,

  /// The platform returned a failure tela does not recognize yet.
  unknown,
}

/// A safe, domain-owned wallpaper-apply error.
///
/// It intentionally excludes the source URL and vendor error message so neither
/// can leak through logs or UI by accident.
class WallpaperApplyFailure implements Exception {
  /// Creates a failure describing [problem].
  const WallpaperApplyFailure(this.problem);

  /// The actionable category of the failure.
  final WallpaperApplyProblem problem;

  @override
  String toString() => 'WallpaperApplyFailure(${problem.name})';
}
