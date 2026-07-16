import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/ports/app_lock.dart';
import 'package:tela/domain/ports/screen_guard.dart';
import 'package:tela/features/private_library/private_unlock_session.dart';

/// The secure-access lifecycle shared by the app-private tier's two screens.
///
/// Both the grid and the fullscreen viewer must hold `FLAG_SECURE` for as long
/// as they are on screen and must refuse to show anything until the app-lock is
/// satisfied. Neither leans on the other: the viewer is pushed *over* the grid,
/// but a window flag is not a route, and the gate is defence in depth rather
/// than a gate on whatever opened it. The [ScreenGuard] is reference-counted,
/// so both holding it keeps the window protected across the whole private flow.
///
/// Defence in depth is about the *gate*, not the *toll*. Both screens gate;
/// only the first one to be reached charges for it, because
/// [privateUnlockSessionProvider] remembers a satisfied lock for as long as the
/// app stays in the foreground. Authenticating twice to see one image was a
/// bug, not the policy.
///
/// A state mixes this in, calls [beginPrivateAccess] from `initState` and
/// [endPrivateAccess] from `dispose`, and gates its body on [isCheckingLock] /
/// [isUnlocked], offering [authenticate] as the retry.
mixin PrivateSecureAccess<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Held in a field rather than re-read on the way out: Riverpod forbids
  /// `ref.read` in `dispose`, and the flag has to be given back exactly when
  /// the screen goes away — there is no later chance to do it.
  late final ScreenGuard _screenGuard;

  bool _unlocked = false;
  bool _checking = true;

  /// True while the lock is being resolved or the system prompt is up.
  bool get isCheckingLock => _checking;

  /// True once the lock has been satisfied; nothing sensitive shows before it.
  bool get isUnlocked => _unlocked;

  /// Takes `FLAG_SECURE` before the first frame and starts the lock check.
  ///
  /// The flag is claimed before content: a thumbnail can be captured the moment
  /// a route is on screen, so asking for it later is asking too late.
  void beginPrivateAccess() {
    _screenGuard = ref.read(screenGuardProvider);
    unawaited(_screenGuard.setSecure(secure: true));
    unawaited(_unlock());
  }

  /// Gives `FLAG_SECURE` back. Balanced against [beginPrivateAccess].
  void endPrivateAccess() {
    unawaited(_screenGuard.setSecure(secure: false));
  }

  /// Resolves the lock before anything is shown.
  ///
  /// The gate lives in each screen rather than on whatever opened it, because a
  /// route can be reached more ways than one — gating a button would leave the
  /// content one deep link away from being shown ungated. That argument is
  /// about *where the gate lives*, though, not about how often the owner pays:
  /// a lock satisfied moments ago on the grid is satisfied for the viewer it
  /// opens, so an already-paid toll is inherited from
  /// [privateUnlockSessionProvider] rather than charged again. Backgrounding
  /// revokes it there, and a screen reached cold still prompts.
  Future<void> _unlock() async {
    final bool locked = await ref
        .read(settingsRepositoryProvider)
        .isPrivateLibraryLocked();
    if (!locked) {
      if (mounted) setState(() => _pass(unlocked: true));
      return;
    }
    if (ref.read(privateUnlockSessionProvider)) {
      if (mounted) setState(() => _pass(unlocked: true));
      return;
    }
    await authenticate();
  }

  /// Raises the biometric/PIN prompt; only a pass opens the content.
  ///
  /// **It fails closed.** Only [AppLockOutcome.passed] gets in — including over
  /// [AppLockOutcome.unavailable]. `isAvailable` can't tell "this device has no
  /// credentials" apart from "the sensor is locked out for 30 seconds", and it
  /// reports both as false; on a device whose only credential is a fingerprint,
  /// consulting it turned five bad reads into an open door (found on hardware,
  /// 2026-07-14). The owner's way back in is the Settings switch, which stays
  /// operable precisely for this — a lock you can turn off is not a trap, but a
  /// lock that opens itself is not a lock.
  Future<void> authenticate() async {
    if (mounted) setState(() => _checking = true);
    final AppLockOutcome outcome = await ref
        .read(appLockProvider)
        .authenticate(
          reason: AppLocalizations.of(context).privateLibraryUnlockReason,
        );
    final bool passed = outcome == AppLockOutcome.passed;
    // Only a genuine pass is worth inheriting; a failure leaves the session as
    // locked as it found it.
    if (passed) ref.read(privateUnlockSessionProvider.notifier).grant();
    if (mounted) setState(() => _pass(unlocked: passed));
  }

  void _pass({required bool unlocked}) {
    _unlocked = unlocked;
    _checking = false;
  }
}
