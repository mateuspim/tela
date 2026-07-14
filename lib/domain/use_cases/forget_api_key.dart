import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Removes the stored Wallhaven API key, and the account defaults it unlocked.
///
/// NSFW becomes unreachable again the moment this returns: `SearchWallpapers`
/// refuses an explicit query with no key, and the settings screen stops
/// offering the NSFW purity.
///
/// The synced defaults go with it, because they may *be* an explicit purity —
/// they belong to an account this device can no longer reach, and browsing on
/// them without a key is a guaranteed 401 rather than a grid. Browse falls back
/// to tela's own defaults, which is where it started.
///
/// ```dart
/// await forgetApiKey();
/// ```
class ForgetApiKey {
  /// Creates the use case over the key store and the settings store.
  const ForgetApiKey({
    required SecretStore secrets,
    required SettingsRepository settings,
  }) : _secrets = secrets,
       _settings = settings;

  final SecretStore _secrets;
  final SettingsRepository _settings;

  /// Deletes the key and the synced defaults. Neither having been there is not
  /// an error.
  ///
  /// The key goes first: it is the secret, and if the second write somehow
  /// failed, `LoadAccountDefaults` still refuses to hand an explicit default to
  /// a device with no key.
  Future<void> call() async {
    await _secrets.deleteApiKey();
    await _settings.forgetAccountDefaults();
  }
}
