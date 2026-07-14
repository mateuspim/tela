import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Downloads a wallpaper to the destination its purity is configured for.
class DownloadWallpaper {
  /// Creates the use case over the storage, settings, and history seams.
  const DownloadWallpaper({
    required ImageStore imageStore,
    required SettingsRepository settings,
    required DownloadHistory history,
  }) : _imageStore = imageStore,
       _settings = settings,
       _history = history;

  final ImageStore _imageStore;
  final SettingsRepository _settings;
  final DownloadHistory _history;

  /// Stores [wallpaper], preserving its purity so the adapter routes it safely,
  /// and records where it landed so it can be set again without a second fetch.
  ///
  /// [tier] is the per-download override; without it the wallpaper goes to the
  /// tier the user configured for its purity.
  ///
  /// ```dart
  /// await download(wallpaper); // the configured destination
  /// await download(wallpaper, tier: StorageTier.appPrivate); // just this once
  /// ```
  Future<StoredImage> call(Wallpaper wallpaper, {StorageTier? tier}) async {
    final StorageTier destination = tier ?? await _configuredTier(wallpaper);
    final StoredImage stored = await _imageStore.store(
      id: wallpaper.id,
      imageUrl: wallpaper.fullImageUrl,
      purity: wallpaper.purity,
      tier: destination,
    );
    await _remember(wallpaper, stored);
    return stored;
  }

  /// Records the download, except for an explicit one.
  ///
  /// The purity check is here *and* in the adapter, the same way the NSFW
  /// storage rule is enforced twice: an explicit wallpaper's home is the
  /// private library, not a browsable, backed-up row on an ungated screen.
  Future<void> _remember(Wallpaper wallpaper, StoredImage stored) async {
    if (wallpaper.isNsfw) return;
    await _history.record(
      wallpaper: wallpaper,
      tier: stored.tier,
      location: stored.location,
    );
  }

  Future<StorageTier> _configuredTier(Wallpaper wallpaper) async {
    final StorageSettings settings = await _settings.loadStorageSettings();
    return settings.tierFor(wallpaper.purity);
  }
}
