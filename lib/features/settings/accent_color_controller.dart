import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// The user's chosen brand accent, or null to follow the device palette.
///
/// Watched by both the theme (to paint it) and the settings screen (to show
/// which swatch is on). One source, so a change on the settings screen retints
/// the whole app without either side reaching for the other.
final AsyncNotifierProvider<AccentColorController, AccentColor?>
accentColorProvider =
    AsyncNotifierProvider<AccentColorController, AccentColor?>(
      AccentColorController.new,
    );

/// Loads the accent and writes changes straight back through the port.
///
/// There is no save button, as with the other settings controllers: a screen
/// that can be closed mid-edit should not be able to lose the edit.
class AccentColorController extends AsyncNotifier<AccentColor?> {
  @override
  Future<AccentColor?> build() {
    return ref.watch(settingsRepositoryProvider).loadAccentColor();
  }

  /// Adopts [accent] as tela's brand colour from now on.
  Future<void> choose(AccentColor accent) async {
    if (state.value == accent) return;
    // Persist before showing it: a swatch that lit up but did not save would be
    // an accent the user believes is set. The write is a local SQLite upsert.
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    await settings.saveAccentColor(accent);
    state = AsyncData<AccentColor?>(accent);
  }

  /// Drops the chosen accent, so the chrome follows the device palette again.
  Future<void> followSystem() async {
    if (state.value == null) return;
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    await settings.clearAccentColor();
    state = const AsyncData<AccentColor?>(null);
  }
}
