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
  Future<bool> authenticate({required String reason}) async {
    try {
      // `biometricOnly` stays at its default of false on purpose: a fingerprint
      // that stops reading must not lock someone out of their own files, so the
      // device PIN is always an acceptable answer.
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } on PlatformException {
      // No hardware, no enrolled credential, too many attempts — all of it
      // means "not proven", never "let them in".
      return false;
    }
  }
}
