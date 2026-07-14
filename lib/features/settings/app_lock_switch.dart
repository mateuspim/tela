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
/// Renders nothing on a device with no biometric and no screen lock: there,
/// enabling it would be a switch that silently protects nothing, and the gate
/// itself steps aside so nobody is locked out of their own files.
class AppLockSwitch extends ConsumerWidget {
  /// Creates the app-lock toggle.
  const AppLockSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool available = ref.watch(appLockAvailableProvider).value ?? false;
    if (!available) return _unavailable(context, l10n);

    final bool locked = ref.watch(privateLibraryLockedProvider).value ?? false;
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: Text(l10n.settingsAppLockTitle),
      subtitle: Text(l10n.settingsAppLockDetail),
      value: locked,
      onChanged: (bool value) => _setLocked(ref, locked: value),
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

  Future<void> _setLocked(WidgetRef ref, {required bool locked}) async {
    await ref
        .read(settingsRepositoryProvider)
        .setPrivateLibraryLocked(locked: locked);
    ref.invalidate(privateLibraryLockedProvider);
  }
}
