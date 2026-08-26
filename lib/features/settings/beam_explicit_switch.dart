import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Whether explicit wallpapers may be beamed to a machine on the LAN.
///
/// **The single safeguard behind tela's one deliberate exception to "explicit
/// pixels never leave the app"** — see `mayBeamBitmap`. It starts off, and the
/// only way it becomes true is someone turning it on here, which is what makes
/// a mis-tap on a private-library tile unable to put an explicit file on a
/// desktop.
final AsyncNotifierProvider<ExplicitBeamController, bool> explicitBeamProvider =
    AsyncNotifierProvider<ExplicitBeamController, bool>(
      ExplicitBeamController.new,
    );

/// Loads the gate and writes a change straight back through the port.
///
/// Same no-save-button shape as the other settings controllers: a screen that
/// can be closed mid-edit should not be able to lose the edit.
class ExplicitBeamController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(settingsRepositoryProvider).loadExplicitBeamAllowed();
  }

  /// Allows or forbids beaming explicit wallpapers.
  Future<void> set({required bool allowed}) async {
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    // Persisted before the switch moves: a gate that lit up but did not save
    // is one the user believes is on until the next cold start says otherwise
    // — and this particular gate is the one it matters most to be wrong about.
    await settings.setExplicitBeamAllowed(allowed: allowed);
    state = AsyncData<bool>(allowed);
  }
}

/// The privacy-section switch for the explicit beam.
class BeamExplicitSwitch extends ConsumerWidget {
  /// Creates the toggle.
  const BeamExplicitSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool allowed = ref.watch(explicitBeamProvider).value ?? false;

    return SwitchListTile(
      secondary: const Icon(Icons.wifi_tethering),
      title: Text(l10n.settingsBeamExplicit),
      subtitle: Text(l10n.settingsBeamExplicitDescription),
      value: allowed,
      onChanged: (bool value) => unawaited(
        ref.read(explicitBeamProvider.notifier).set(allowed: value),
      ),
    );
  }
}
