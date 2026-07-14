import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Downloads a wallpaper to the destination its purity is configured for.
class DownloadWallpaper {
  /// Creates the use case over the storage and settings seams.
  const DownloadWallpaper({
    required ImageStore imageStore,
    required SettingsRepository settings,
  }) : _imageStore = imageStore,
       _settings = settings;

  final ImageStore _imageStore;
  final SettingsRepository _settings;

  /// Stores [wallpaper], preserving its purity so the adapter routes it safely.
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
    return _imageStore.store(
      id: wallpaper.id,
      imageUrl: wallpaper.fullImageUrl,
      purity: wallpaper.purity,
      tier: destination,
    );
  }

  Future<StorageTier> _configuredTier(Wallpaper wallpaper) async {
    final StorageSettings settings = await _settings.loadStorageSettings();
    return settings.tierFor(wallpaper.purity);
  }
}
