import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// The "Keep sending here" pin, and the one way the UI reads or changes it.
///
/// It exists as a controller rather than as three direct calls to
/// `SettingsRepository.setPinnedDownloadTier` because of what the pin *does*:
/// once set it silences the destination chooser everywhere — the quick sheet,
/// the batch bar and the detail screen all route silently — so it is a setting
/// the user stops being shown the moment it takes effect. A value like that
/// needs exactly one owner, or the screen that offers to clear it will read a
/// copy written somewhere else and disagree.
final AsyncNotifierProvider<PinnedDownloadTier, StorageTier?>
pinnedDownloadTierProvider =
    AsyncNotifierProvider<PinnedDownloadTier, StorageTier?>(
      PinnedDownloadTier.new,
    );

/// Loads the pin and writes changes straight back through the port.
class PinnedDownloadTier extends AsyncNotifier<StorageTier?> {
  @override
  Future<StorageTier?> build() {
    return ref.watch(settingsRepositoryProvider).loadPinnedDownloadTier();
  }

  /// Sends every later download to [tier] without asking again.
  Future<void> pin(StorageTier tier) => _write(tier);

  /// Stops the pin, so downloads go back to asking where they land.
  Future<void> clear() => _write(null);

  Future<void> _write(StorageTier? tier) async {
    // Persist before publishing: a chooser that closed on a pin which did not
    // save would be a setting the user believes is on.
    await ref.read(settingsRepositoryProvider).setPinnedDownloadTier(tier);
    state = AsyncData<StorageTier?>(tier);
  }
}
