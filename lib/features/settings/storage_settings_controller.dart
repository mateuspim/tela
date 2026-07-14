import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// The persisted download routing, and the one way the UI changes it.
final AsyncNotifierProvider<StorageSettingsController, StorageSettings>
storageSettingsProvider =
    AsyncNotifierProvider<StorageSettingsController, StorageSettings>(
      StorageSettingsController.new,
    );

/// Loads storage settings and writes changes straight back through the port.
///
/// There is no save button: a settings screen that can be closed mid-edit
/// should not be able to lose the edit.
class StorageSettingsController extends AsyncNotifier<StorageSettings> {
  @override
  Future<StorageSettings> build() {
    return ref.watch(settingsRepositoryProvider).loadStorageSettings();
  }

  /// Sends downloads of [purity] to [tier] from now on.
  Future<void> route(Purity purity, StorageTier tier) async {
    final StorageSettings? current = state.value;
    if (current == null) return;

    final StorageSettings updated = purity == Purity.nsfw
        ? current.copyWith(nsfwTier: tier)
        : current.copyWith(sfwTier: tier);
    if (updated == current) return;

    // Persist before showing it: a radio that moved but did not save would be a
    // setting the user believes is on. The write is a local SQLite upsert.
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    await settings.saveStorageSettings(updated);
    state = AsyncData<StorageSettings>(updated);
  }
}
