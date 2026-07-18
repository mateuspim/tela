import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/tile_density.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// How large the wallpaper shelves draw their tiles.
///
/// Watched by the app root (which publishes it to every shelf through a
/// `TileDensityScope`) and by the settings screen (to show which step is on).
/// One source, so choosing a density on the settings screen resizes the wall
/// behind it without either side reaching for the other.
final AsyncNotifierProvider<TileDensityController, TileDensity>
tileDensityProvider = AsyncNotifierProvider<TileDensityController, TileDensity>(
  TileDensityController.new,
);

/// Loads the density and writes changes straight back through the port.
///
/// No save button, as with the other settings controllers: a screen that can be
/// closed mid-edit should not be able to lose the edit.
class TileDensityController extends AsyncNotifier<TileDensity> {
  @override
  Future<TileDensity> build() {
    return ref.watch(settingsRepositoryProvider).loadTileDensity();
  }

  /// Draws the shelves at [density] from now on.
  Future<void> choose(TileDensity density) async {
    if (state.value == density) return;
    // Persist before showing it: a step that lit up but did not save would be a
    // density the user believes is set. The write is a local SQLite upsert.
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    await settings.saveTileDensity(density);
    state = AsyncData<TileDensity>(density);
  }
}
