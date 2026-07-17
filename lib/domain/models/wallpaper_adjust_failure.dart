/// Why Android could not open its own editor for a wallpaper.
enum WallpaperAdjustProblem {
  /// The full-resolution image could not be fetched to hand to the editor.
  source,

  /// Nothing on this device offers to crop and set a wallpaper. Some ROMs ship
  /// no such activity at all, so this is a normal answer rather than a defect.
  unavailable,

  /// Android refused the image itself — it reached the editor as something
  /// other than a readable `image/*`, which is the platform's own precondition.
  unsupportedImage,

  /// The platform returned a failure tela does not recognize yet.
  unknown,
}

/// A safe, domain-owned wallpaper-adjust error.
///
/// Like `WallpaperApplyFailure` and `WallpaperShareFailure`, it excludes the
/// source URL and the vendor message so neither can leak through logs or UI by
/// accident.
class WallpaperAdjustFailure implements Exception {
  /// Creates a failure describing [problem].
  const WallpaperAdjustFailure(this.problem);

  /// The actionable category of the failure.
  final WallpaperAdjustProblem problem;

  @override
  String toString() => 'WallpaperAdjustFailure(${problem.name})';
}
