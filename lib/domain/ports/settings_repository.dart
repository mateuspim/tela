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

  /// Whether the private library asks for a biometric or PIN before it opens.
  ///
  /// The lock is opt-in, so a setting that was never written answers `false`. A
  /// setting that was written but cannot be *read* answers `true`: "I can't
  /// tell whether this was locked" has only one safe reading. Never throws.
  Future<bool> isPrivateLibraryLocked();

  /// Turns the private library's lock on or off.
  Future<void> setPrivateLibraryLocked({required bool locked});
}
