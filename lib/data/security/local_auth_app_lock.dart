import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:tela/domain/ports/app_lock.dart';

/// [AppLock] backed by Android's BiometricPrompt, via `local_auth`.
///
/// Requires the host activity to be a `FlutterFragmentActivity`; a plain
/// `FlutterActivity` throws at prompt time, not at build time.
class LocalAuthAppLock implements AppLock {
  /// Creates the adapter over a `local_auth` instance.
  LocalAuthAppLock({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      // Covers the device credential (PIN/pattern/password) as well as
      // biometrics — which is exactly the set `authenticate` will accept.
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<AppLockOutcome> authenticate({required String reason}) async {
    try {
      // `biometricOnly` stays at its default of false on purpose: a fingerprint
      // that stops reading must not lock someone out of their own files, so the
      // device PIN is always an acceptable answer — on a device that has one.
      final bool passed = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
      return passed ? AppLockOutcome.passed : AppLockOutcome.refused;
    } on PlatformException catch (error) {
      return _outcomeOf(error.code);
    }
  }

  /// Maps `local_auth`'s error codes to what the rule actually turns on.
  ///
  /// The split that matters is lockout versus no-credentials: a lockout is the
  /// lock doing its job and must keep the library shut, while an unaskable
  /// device is the only case allowed to stand in for a pass (and only to switch
  /// the lock off). Anything unrecognised is [AppLockOutcome.refused] — the
  /// safe reading, since an unknown error is not proof of anything.
  AppLockOutcome _outcomeOf(String code) {
    return switch (code) {
      'LockedOut' || 'PermanentlyLockedOut' => AppLockOutcome.lockedOut,
      'NotAvailable' || 'NotEnrolled' => AppLockOutcome.unavailable,
      _ => AppLockOutcome.refused,
    };
  }
}
