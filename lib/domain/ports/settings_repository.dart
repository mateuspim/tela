import 'package:tela/domain/models/account_settings.dart';
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

  /// The Wallhaven account's browse defaults as this device last synced them,
  /// or null when no key has ever been saved.
  ///
  /// Never throws: a row it cannot read answers null, and null simply means
  /// tela browses on its own defaults.
  Future<AccountSettings?> loadAccountDefaults();

  /// Persists [account] as the defaults a fresh listing starts from.
  Future<void> saveAccountDefaults(AccountSettings account);

  /// Drops the synced defaults, which is what forgetting the API key does.
  ///
  /// They belong to an account this device can no longer reach: an explicit
  /// purity outlives its key by exactly one 401 otherwise.
  Future<void> forgetAccountDefaults();
}
