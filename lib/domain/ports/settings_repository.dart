import 'package:tela/domain/models/storage_settings.dart';

/// Reads and writes the user's persisted preferences.
///
/// A pure-domain port: no package sits behind it, and the fact that its adapter
/// speaks SQL is not something a feature or a use case may observe.
abstract interface class SettingsRepository {
  /// The current storage routing, or [StorageSettings.defaults] when unset.
  ///
  /// Never throws: unreadable or corrupt storage falls back to the defaults,
  /// because a download must still have somewhere safe to go.
  Future<StorageSettings> loadStorageSettings();

  /// Persists [settings] as the new storage routing.
  Future<void> saveStorageSettings(StorageSettings settings);
}
