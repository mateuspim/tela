import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
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

  final TelaDatabase _db;

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
    await _db.putSetting(_accountCategoriesKey, account.categories.toApiBits());
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
    );
  }

  @override
  Future<void> saveDeviceDefaults(BrowseDefaults defaults) async {
    await _db.putSetting(_deviceCategoriesKey, defaults.categories.toApiBits());
    await _db.putSetting(_deviceTopRangeKey, defaults.topRange.apiValue);
    await _db.putSetting(_deviceRatiosKey, defaults.encodedRatios());
    await _db.putSetting(_deviceOrderKey, defaults.order.name);
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
