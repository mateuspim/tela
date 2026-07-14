import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
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
  static const String _accountPurityKey = 'account.purity';
  static const String _accountTopRangeKey = 'account.topRange';

  /// Every row [forgetAccountDefaults] drops. The defaults are one setting.
  static const List<String> _accountKeys = <String>[
    _accountCategoriesKey,
    _accountPurityKey,
    _accountTopRangeKey,
  ];

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
    final String? purity = await _db.settingValue(_accountPurityKey);
    final String? topRange = await _db.settingValue(_accountTopRangeKey);
    if (categories == null || purity == null || topRange == null) return null;

    // A row that cannot be read costs the defaults, not the app: browse simply
    // opens on tela's own, which is where it opens before any key is saved.
    return AccountSettings.tryParse(
      storedCategories: categories,
      storedPurity: purity,
      storedTopRange: topRange,
    );
  }

  @override
  Future<void> saveAccountDefaults(AccountSettings account) async {
    await _db.putSetting(_accountCategoriesKey, account.categories.toApiBits());
    await _db.putSetting(_accountPurityKey, account.purity.toApiBits());
    await _db.putSetting(_accountTopRangeKey, account.topRange.apiValue);
  }

  @override
  Future<void> forgetAccountDefaults() => _db.deleteSettings(_accountKeys);

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
