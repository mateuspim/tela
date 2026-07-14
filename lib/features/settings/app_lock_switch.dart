import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/ports/app_lock.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Whether this device can ask for a biometric or a device PIN at all.
final FutureProvider<bool> appLockAvailableProvider = FutureProvider<bool>((
  Ref ref,
) {
  final AppLock lock = ref.watch(appLockProvider);
  return lock.isAvailable();
});

/// Whether the private library currently asks for one.
final FutureProvider<bool> privateLibraryLockedProvider = FutureProvider<bool>((
  Ref ref,
) {
  final SettingsRepository settings = ref.watch(settingsRepositoryProvider);
  return settings.isPrivateLibraryLocked();
});

/// Turns the private library's biometric/PIN gate on and off.
///
/// **Turning it off is itself gated**, and it has to be: the gate on the
/// library is worth exactly nothing if the switch that disables it is one tap
/// away on an open screen. So switching *off* raises the same prompt the
/// library does, and only a pass — or a device that cannot ask (below) —
/// writes the setting.
///
/// Switching *on* is not gated. There is nothing to prove yet, and demanding a
/// fingerprint to *add* protection only teaches people not to bother.
class AppLockSwitch extends ConsumerStatefulWidget {
  /// Creates the app-lock toggle.
  const AppLockSwitch({super.key});

  @override
  ConsumerState<AppLockSwitch> createState() => _AppLockSwitchState();
}

class _AppLockSwitchState extends ConsumerState<AppLockSwitch> {
  /// True while the system prompt is up, so a second tap cannot stack another.
  bool _asking = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool available = ref.watch(appLockAvailableProvider).value ?? false;
    final bool locked = ref.watch(privateLibraryLockedProvider).value ?? false;

    // Nothing to offer: the lock cannot be satisfied and is not on, so turning
    // it on would be a switch that silently protects nothing. (Once it *is* on,
    // the switch stays — turning it back off is the way out, and that path is
    // handled by the prompt below.)
    if (!available && !locked) return _unavailable(context, l10n);

    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: Text(l10n.settingsAppLockTitle),
      subtitle: Text(l10n.settingsAppLockDetail),
      value: locked,
      onChanged: _asking ? null : (bool value) => unawaited(_toggle(value)),
    );
  }

  Widget _unavailable(BuildContext context, AppLocalizations l10n) {
    return ListTile(
      leading: const Icon(Icons.fingerprint),
      title: Text(l10n.settingsAppLockTitle),
      subtitle: Text(l10n.settingsAppLockUnavailable),
      enabled: false,
    );
  }

  /// Writes [locked], asking for proof first when it would *remove* the lock.
  Future<void> _toggle(bool locked) async {
    if (locked) return _setLocked(locked: true);
    if (!await _provedIdentity()) return;
    await _setLocked(locked: false);
  }

  /// Whether the person at the phone may switch the lock off.
  ///
  /// [AppLockOutcome.unavailable] passes, and it is the *only* outcome besides
  /// a real pass that does: a device with no enrolled biometric and no screen
  /// lock can never answer a prompt, and app-private files live nowhere else —
  /// refusing here would strand the owner outside their own library for good.
  ///
  /// [AppLockOutcome.lockedOut] is refused, and that distinction is the entire
  /// reason this port stopped returning a bool. Five failed reads is what a
  /// stranger's finger looks like; if a lockout opened this switch, failing the
  /// fingerprint five times *would be* the way past the lock.
  Future<bool> _provedIdentity() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _asking = true);
    try {
      final AppLockOutcome outcome = await ref
          .read(appLockProvider)
          .authenticate(reason: l10n.settingsAppLockDisableReason);
      if (outcome == AppLockOutcome.lockedOut && mounted) {
        _show(l10n.settingsAppLockLockedOut);
      }
      return outcome == AppLockOutcome.passed ||
          outcome == AppLockOutcome.unavailable;
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _setLocked({required bool locked}) async {
    await ref
        .read(settingsRepositoryProvider)
        .setPrivateLibraryLocked(locked: locked);
    ref.invalidate(privateLibraryLockedProvider);
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
