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
  /// Two records, and they are not the same record. [_remember] writes a
  /// browsable history row and withholds it for explicit and private downloads;
  /// `recordDestination` writes a tier and a count with no wallpaper identity
  /// in it at all, and so is written for **every** download — including the
  /// ones the history must drop, which are exactly the ones the destination
  /// memory exists to notice.
  ///
  /// Both read [StoredImage.tier] rather than the requested one: the adapter
  /// has the last word on where a file actually went.
  ///
  /// [tier] is the per-download override; without it the wallpaper goes to the
  /// pinned "Keep sending here" destination, or the tier the user configured
  /// for its purity when no pin is set. The precedence is: the per-download
  /// [tier] > the pin > the configured tier.
  ///
  /// ```dart
  /// await download(wallpaper); // the pin, or the configured destination
  /// await download(wallpaper, tier: StorageTier.appPrivate); // just this once
  /// ```
  Future<StoredImage> call(Wallpaper wallpaper, {StorageTier? tier}) async {
    final StorageTier destination = tier ?? await _defaultTier(wallpaper);
    final StoredImage stored = await _imageStore.store(
      source: wallpaper.ref.source,
      id: wallpaper.ref.id,
      imageUrl: wallpaper.fullImageUrl,
      purity: wallpaper.purity,
      tier: destination,
    );
    await _remember(wallpaper, stored);
    await _settings.recordDestination(wallpaper.purity, stored.tier);
    return stored;
  }

  /// Records the download, except for an explicit one or a private one.
  ///
  /// Both checks are here *and* in the adapter, the same way the NSFW storage
  /// rule is enforced twice: an explicit wallpaper's home is the private
  /// library, not a browsable, backed-up row on an ungated screen.
  ///
  /// The destination check is the one purity cannot stand in for. It reads
  /// [StoredImage.tier] — where the file actually *landed* — rather than the
  /// requested tier, so the adapter has the last word on it. A safe wallpaper
  /// sent to the private tier is still a private download, and it was the
  /// per-download override that made that ordinary rather than exotic.
  Future<void> _remember(Wallpaper wallpaper, StoredImage stored) async {
    if (wallpaper.isNsfw) return;
    if (stored.tier == StorageTier.appPrivate) return;
    await _history.record(
      wallpaper: wallpaper,
      tier: stored.tier,
      location: stored.location,
    );
  }

  /// The destination a plain download lands in: the pin when one is set and
  /// legal for this purity, else the configured tier.
  ///
  /// The invariant fallback — an explicit wallpaper under a `sharedGallery` pin
  /// dropping to its configured private tier — lives in
  /// [StorageSettings.tierWithPin], so it is enforced in the domain and not
  /// re-derived per caller.
  Future<StorageTier> _defaultTier(Wallpaper wallpaper) async {
    final StorageTier? pin = await _settings.loadPinnedDownloadTier();
    final StorageSettings settings = await _settings.loadStorageSettings();
    return settings.tierWithPin(wallpaper.purity, pin);
  }
}
