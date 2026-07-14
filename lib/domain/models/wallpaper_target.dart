/// The Android surface that receives a wallpaper.
///
/// This domain enum deliberately does not expose Android or plugin constants.
/// Adapters translate it at the platform boundary.
enum WallpaperTarget {
  /// Apply only to the launcher behind the app icons.
  home,

  /// Apply only to the lock screen.
  lock,

  /// Apply to the launcher and lock screen.
  both,
}
