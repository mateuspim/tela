/// How an [AppLock] prompt ended.
///
/// A bool used to be enough, and it was not: "the sensor is locked out for the
/// next 30 seconds" and "this device has no credentials at all" are the same
/// `false`, and telling them apart is the difference between a lock and a hole.
/// The first is the lock *working* — five bad reads is what a stranger's finger
/// looks like — and must keep the library shut. The second is a device that can
/// never answer, where refusing forever would strand the owner outside files
/// that live nowhere else. Found on hardware, 2026-07-14.
enum AppLockOutcome {
  /// Proven. The only value that opens anything.
  passed,

  /// Asked and not proven: a wrong finger, a cancelled prompt, a dismissed one.
  refused,

  /// Too many failed attempts. Temporary (30 seconds) or until a strong
  /// credential is used — either way the lock is *working*, so this must never
  /// be treated as "cannot ask".
  lockedOut,

  /// This device has nothing to ask with: no biometric enrolled and no screen
  /// lock. The only outcome that may stand in for a pass, and only ever to let
  /// the owner switch the lock back off.
  unavailable,
}

/// Asks the person holding the phone to prove they own it.
///
/// Biometric or device credential (PIN, pattern, password), behind a port so
/// the domain can state the rule without importing a plugin. Gates the private
/// library, per CLAUDE.md.
abstract interface class AppLock {
  /// Whether this device can ask for anything at all.
  ///
  /// **Only ever a reason to withhold the setting, never a reason to open
  /// anything.** It cannot distinguish a locked-out sensor from a device with
  /// no credentials — both answer false — so a gate that consults it lets a
  /// stranger in by failing the fingerprint five times. Use
  /// [AppLockOutcome.unavailable] from an actual [authenticate] for that
  /// question; this one is fit only for deciding whether to offer a lock that
  /// nothing could satisfy.
  Future<bool> isAvailable();

  /// Prompts, and says how it ended.
  ///
  /// [reason] is shown by the system dialog and must be localized by the
  /// caller. Never throws: every platform error maps to an outcome, so an
  /// exception cannot be mistaken for a pass.
  Future<AppLockOutcome> authenticate({required String reason});
}
