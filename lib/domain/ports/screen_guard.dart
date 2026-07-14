/// Hides a screen's contents from the OS.
///
/// Android's `FLAG_SECURE`, behind a port so the domain can state the rule
/// without importing a window API: while it is on, the screen cannot be
/// screenshotted, cannot be recorded, and does not appear in the app switcher's
/// thumbnail. CLAUDE.md requires it for the private library.
///
/// ```dart
/// await screenGuard.setSecure(secure: true);   // entering the private library
/// await screenGuard.setSecure(secure: false);  // leaving it
/// ```
abstract interface class ScreenGuard {
  /// Turns the protection on or off for the app's window.
  Future<void> setSecure({required bool secure});
}
