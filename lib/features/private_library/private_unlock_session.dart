import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app-lock has already been satisfied in this foreground session.
final NotifierProvider<PrivateUnlockSession, bool>
privateUnlockSessionProvider = NotifierProvider<PrivateUnlockSession, bool>(
  PrivateUnlockSession.new,
);

/// The app-lock toll, paid once per foreground session rather than per screen.
///
/// The *gate* still lives on every private screen — see `PrivateSecureAccess`,
/// whose reasoning this does not weaken: a route can be reached more ways than
/// one, so gating whatever opened it would leave the content one deep link away
/// from being shown ungated. What is hoisted here is only whether the toll has
/// **already been paid**, so a viewer opened over an unlocked grid inherits the
/// unlock instead of asking the owner to authenticate twice to see one image.
/// A viewer reached cold has nothing to inherit, and still prompts.
///
/// It fails closed on the way out: backgrounding revokes the unlock, so the
/// next entry pays again. The lifecycle listener lives here rather than in the
/// mixin because the unlock outlives both screens — nothing private need be
/// mounted at the moment the app goes away, and a revoke that only happens
/// while the grid is watching is not a revoke.
///
/// ```dart
/// if (ref.read(privateUnlockSessionProvider)) return; // already paid
/// ```
class PrivateUnlockSession extends Notifier<bool> {
  @override
  bool build() {
    final AppLifecycleListener listener = AppLifecycleListener(
      onStateChange: _onLifecycle,
    );
    ref.onDispose(listener.dispose);
    return false;
  }

  /// Revokes the moment the app is on its way out of the foreground.
  ///
  /// `inactive` is deliberately *not* backgrounding: the biometric prompt
  /// itself raises it, and revoking there would fight the very unlock being
  /// granted. Everything past it is, so all three revoke.
  void _onLifecycle(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        state = false;
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Records a satisfied lock, so this session's other private screens inherit
  /// it. Only ever called for a genuine pass — never for a refusal, a lockout,
  /// or an unaskable device, all of which leave the toll owed.
  void grant() => state = true;
}
