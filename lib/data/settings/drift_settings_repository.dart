import 'package:tela/data/db/tela_database.dart';
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
