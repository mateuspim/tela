import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tile_density.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Stores settings as key/value rows in tela's SQLite database.
///
/// ```dart
/// final SettingsRepository settings = DriftSettingsRepository(db);
/// await settings.saveStorageSettings(StorageSettings.defaults);
/// ```
class DriftSettingsRepository implements SettingsRepository {
  /// Creates the adapter over an open [TelaDatabase].
  const DriftSettingsRepository(this._db);

  /// Row keys. Values are [StorageTier] names, so a renamed enum constant is a
  /// migration, not a silent reset — hence the parse falling back to defaults.
  static const String _sfwKey = 'storage.tier.sfw';
  static const String _nsfwKey = 'storage.tier.nsfw';

  /// A new setting is a new row, never a migration — see the v1 schema note.
  static const String _privateLockKey = 'privacy.privateLibraryLock';

  /// The one-time nod that explicit downloads may land on a removable card.
  /// Stored as `'true'`/`'false'`; anything else, or absent, reads as *not*
  /// acknowledged — a warning fails open so it is shown, not skipped.
  static const String _nsfwOnRemovableAckKey = 'privacy.nsfwOnRemovableAck';

  /// The synced account defaults, stored as the wire literals Wallhaven itself
  /// uses (`"110"`, `"1M"`). They are the values' canonical form, they survive
  /// an enum constant being renamed, and they read the same in a `sqlite3`
  /// shell as they do in a request.
  static const String _accountCategoriesKey = 'account.categories';
  static const String _accountTopRangeKey = 'account.topRange';

  /// Written by builds between `9dd0d6a` and `76471d3`, which synced the
  /// account's purity before that turned out to open browse on explicit content
  /// (see `AccountSettings`). Nothing reads it any more, so it is only here to
  /// be deleted — an inert row saying `purity=111` is exactly the thing that
  /// misleads whoever next opens this database.
  static const String _legacyAccountPurityKey = 'account.purity';

  /// Every row [forgetAccountDefaults] drops. The defaults are one setting.
  static const List<String> _accountKeys = <String>[
    _accountCategoriesKey,
    _accountTopRangeKey,
    _legacyAccountPurityKey,
  ];

  /// Which of the two the user picked. Absent means the account, which is what
  /// every build before the switch browsed on.
  static const String _sourceKey = 'browse.defaults.source';

  /// The device's saved snapshot. Stored as the same wire literals the
  /// account's rows use, and for the same reasons: canonical, rename-proof, and
  /// readable in a `sqlite3` shell. There is deliberately no `device.purity`
  /// row — see [BrowseDefaults].
  static const String _deviceCategoriesKey = 'device.categories';
  static const String _deviceTopRangeKey = 'device.topRange';
  static const String _deviceRatiosKey = 'device.ratios';
  static const String _deviceOrderKey = 'device.order';
  static const String _deviceColorKey = 'device.color';
  static const String _deviceResolutionKey = 'device.resolution';

  /// The user's brand accent, stored as a `#rrggbb` literal — the same form the
  /// picker and a `sqlite3` shell read. Absent means follow the device palette.
  static const String _accentKey = 'appearance.accent';

  /// Which source browse is on, as the `SourceId` value (`wallhaven`).
  /// Absent means Wallhaven, which is where every build before the switcher
  /// browsed.
  static const String _activeSourceKey = 'source.active';

  /// How large the shelves draw their tiles, stored as the [TileDensity]
  /// constant name — so a renamed constant reads back as unset (medium) rather
  /// than as some other density. Absent means medium.
  static const String _densityKey = 'appearance.tileDensity';

  /// Where the last run of downloads landed, one row per storage bucket, as
  /// `tier:count` (see [DownloadDestinationStreak.encode]).
  ///
  /// Two rows and no wallpaper identity — this is the *only* place tela records
  /// anything about an explicit download, and it deliberately cannot say which
  /// wallpaper it was.
  static const String _safeStreakKey = 'downloads.streak.sfw';
  static const String _explicitStreakKey = 'downloads.streak.nsfw';

  /// The "Keep sending here" pin. A [StorageTier] name, or absent when no pin
  /// is set. Purity-flat — one row for all purities.
  static const String _pinnedTierKey = 'downloads.pinned';

  final TelaDatabase _db;

  @override
  Future<SourceId> loadActiveSource() async {
    final String? stored = await _db.settingValue(_activeSourceKey);
    if (stored == null || stored.isEmpty) return SourceId.wallhaven;
    // Taken at face value rather than validated against the registry: this
    // adapter reports what was written, and choosing what to do about a source
    // this build no longer has is the registry's call.
    return SourceId(stored);
  }

  @override
  Future<void> saveActiveSource(SourceId source) {
    return _db.putSetting(_activeSourceKey, source.value);
  }

  @override
  Future<StorageSettings> loadStorageSettings() async {
    final StorageSettings fallback = StorageSettings.defaults;
    return StorageSettings(
      sfwTier: await _tier(_sfwKey, Purity.sfw, fallback.sfwTier),
      nsfwTier: await _tier(_nsfwKey, Purity.nsfw, fallback.nsfwTier),
    );
  }

  @override
  Future<void> saveStorageSettings(StorageSettings settings) async {
    await _db.putSetting(_sfwKey, settings.sfwTier.name);
    await _db.putSetting(_nsfwKey, settings.nsfwTier.name);
  }

  @override
  Future<bool> loadNsfwOnRemovableAcknowledged() async {
    // Absent or corrupt reads as not acknowledged: unlike the private lock,
    // the safe reading of a warning is to show it. Only a literal 'true'
    // suppresses it.
    return await _db.settingValue(_nsfwOnRemovableAckKey) == 'true';
  }

  @override
  Future<void> saveNsfwOnRemovableAcknowledged({required bool acknowledged}) {
    return _db.putSetting(_nsfwOnRemovableAckKey, acknowledged.toString());
  }

  @override
  Future<bool> isPrivateLibraryLocked() async {
    final String? stored = await _db.settingValue(_privateLockKey);
    // Absent means never asked for: the lock is opt-in. Anything else stored
    // there is corrupt, and a corrupt lock setting reads as locked.
    if (stored == null) return false;
    return stored != 'false';
  }

  @override
  Future<void> setPrivateLibraryLocked({required bool locked}) {
    return _db.putSetting(_privateLockKey, locked.toString());
  }

  @override
  Future<AccountSettings?> loadAccountDefaults() async {
    final String? categories = await _db.settingValue(_accountCategoriesKey);
    final String? topRange = await _db.settingValue(_accountTopRangeKey);
    if (categories == null || topRange == null) return null;

    // A row that cannot be read costs the defaults, not the app: browse simply
    // opens on tela's own, which is where it opens before any key is saved.
    return AccountSettings.tryParse(
      storedCategories: categories,
      storedTopRange: topRange,
    );
  }

  @override
  Future<void> saveAccountDefaults(AccountSettings account) async {
    await _db.putSetting(
      _accountCategoriesKey,
      account.categories.encodeStored(),
    );
    await _db.putSetting(_accountTopRangeKey, account.topRange.apiValue);
    // A re-sync is also the moment to drop what an older build wrote here.
    await _db.deleteSettings(<String>[_legacyAccountPurityKey]);
  }

  @override
  Future<void> forgetAccountDefaults() => _db.deleteSettings(_accountKeys);

  @override
  Future<BrowseDefaultsSource> loadBrowseDefaultsSource() async {
    final String? stored = await _db.settingValue(_sourceKey);
    if (stored == null) return BrowseDefaultsSource.account;
    // An unreadable row costs the choice, not the app: the account's defaults
    // are where every build before this switch already opened.
    return BrowseDefaultsSource.tryFromName(stored) ??
        BrowseDefaultsSource.account;
  }

  @override
  Future<void> setBrowseDefaultsSource(BrowseDefaultsSource source) {
    return _db.putSetting(_sourceKey, source.name);
  }

  @override
  Future<BrowseDefaults?> loadDeviceDefaults() async {
    final String? categories = await _db.settingValue(_deviceCategoriesKey);
    final String? topRange = await _db.settingValue(_deviceTopRangeKey);
    final String? ratios = await _db.settingValue(_deviceRatiosKey);
    final String? order = await _db.settingValue(_deviceOrderKey);
    if (categories == null ||
        topRange == null ||
        ratios == null ||
        order == null) {
      return null;
    }

    return BrowseDefaults.tryParse(
      storedCategories: categories,
      storedTopRange: topRange,
      storedRatios: ratios,
      storedOrder: order,
      storedColor: await _db.settingValue(_deviceColorKey),
      // Absent on every snapshot saved before the resolution filter existed,
      // and absent reads as Automatic — which is what those snapshots browsed
      // on. No migration, as every setting since v1.
      storedResolution: await _db.settingValue(_deviceResolutionKey),
    );
  }

  @override
  Future<void> saveDeviceDefaults(BrowseDefaults defaults) async {
    await _db.putSetting(
      _deviceCategoriesKey,
      defaults.categories.encodeStored(),
    );
    await _db.putSetting(_deviceTopRangeKey, defaults.topRange.apiValue);
    await _db.putSetting(_deviceRatiosKey, defaults.encodedRatios());
    await _db.putSetting(_deviceOrderKey, defaults.order.name);
    await _db.putSetting(
      _deviceResolutionKey,
      defaults.encodedResolution(),
    );
    // "Any colour" is the *absence* of the row, not a row saying nothing — an
    // upsert-only save would leave the last swatch behind and quietly re-apply
    // a filter the user just turned off.
    final WallpaperColor? color = defaults.color;
    if (color == null) {
      await _db.deleteSettings(<String>[_deviceColorKey]);
      return;
    }
    await _db.putSetting(_deviceColorKey, color.hex);
  }

  @override
  Future<AccentColor?> loadAccentColor() async {
    return AccentColor.tryFromHex(await _db.settingValue(_accentKey));
  }

  @override
  Future<void> saveAccentColor(AccentColor accent) {
    return _db.putSetting(_accentKey, accent.hex);
  }

  @override
  Future<void> clearAccentColor() => _db.deleteSettings(<String>[_accentKey]);

  @override
  Future<TileDensity> loadTileDensity() async {
    // An absent or unreadable row costs the preference, not the wall: medium is
    // the density every build before this setting drew.
    return TileDensity.tryFromName(await _db.settingValue(_densityKey)) ??
        TileDensity.medium;
  }

  @override
  Future<void> saveTileDensity(TileDensity density) {
    return _db.putSetting(_densityKey, density.name);
  }

  @override
  Future<DownloadDestinationStreak?> loadDestinationStreak(
    Purity purity,
  ) async {
    final DownloadDestinationStreak? streak =
        DownloadDestinationStreak.tryParse(
          await _db.settingValue(_streakKey(purity)),
        );
    if (streak == null) return null;
    // Distrust the row the same way [_tier] does: a hand-edited database
    // claiming an explicit run landed in the gallery must not become a
    // suggestion to route explicit downloads there. An impossible streak is
    // no streak.
    final bool allowed = StorageSettings.choicesFor(
      purity,
    ).contains(streak.tier);
    return allowed ? streak : null;
  }

  @override
  Future<void> recordDestination(Purity purity, StorageTier tier) async {
    final DownloadDestinationStreak? current = await loadDestinationStreak(
      purity,
    );
    await _db.putSetting(
      _streakKey(purity),
      DownloadDestinationStreak.extending(current, tier).encode(),
    );
  }

  @override
  Future<StorageTier?> loadPinnedDownloadTier() async {
    final String? stored = await _db.settingValue(_pinnedTierKey);
    if (stored == null) return null;
    // Distrust the row: an unrecognised name reads as no pin, never a crash.
    // The NSFW invariant is not applied here — a `sharedGallery` pin is legal
    // to store and simply skips explicit downloads at routing time.
    return StorageTier.values
        .where((StorageTier tier) => tier.name == stored)
        .firstOrNull;
  }

  @override
  Future<void> setPinnedDownloadTier(StorageTier? tier) {
    if (tier == null) return _db.deleteSettings(<String>[_pinnedTierKey]);
    return _db.putSetting(_pinnedTierKey, tier.name);
  }

  /// The row a [purity]'s streak lives in, bucketed exactly as its tier is.
  String _streakKey(Purity purity) {
    return StorageSettings.bucketFor(purity) == Purity.nsfw
        ? _explicitStreakKey
        : _safeStreakKey;
  }

  /// Reads one tier, treating an absent, unrecognised, or forbidden row as
  /// [fallback].
  ///
  /// Never throws, and never widens the NSFW rules: a hand-edited database
  /// claiming `nsfw = sharedGallery` does not get to MediaStore-index anything,
  /// it gets the default. A download with no readable setting must still have a
  /// safe destination.
  Future<StorageTier> _tier(
    String key,
    Purity purity,
    StorageTier fallback,
  ) async {
    final String? stored = await _db.settingValue(key);
    if (stored == null) return fallback;
    return StorageSettings.choicesFor(
          purity,
        ).where((StorageTier tier) => tier.name == stored).firstOrNull ??
        fallback;
  }
}
