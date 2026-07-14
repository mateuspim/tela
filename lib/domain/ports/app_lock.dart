/// Asks the person holding the phone to prove they own it.
///
/// Biometric or device credential (PIN, pattern, password), behind a port so
/// the domain can state the rule without importing a plugin. Gates the private
/// library, per CLAUDE.md.
abstract interface class AppLock {
  /// Whether this device can ask for anything at all.
  ///
  /// False on a phone with no biometric hardware *and* no screen lock set. The
  /// lock cannot be offered as a setting there — it would be a switch that
  /// silently protects nothing.
  Future<bool> isAvailable();

  /// Prompts, and answers whether the person passed.
  ///
  /// [reason] is shown by the system dialog and must be localized by the
  /// caller. Returns false on cancel, on failure, and on error: only an actual
  /// success opens the library, so an exception cannot be mistaken for a pass.
  Future<bool> authenticate({required String reason});
}
