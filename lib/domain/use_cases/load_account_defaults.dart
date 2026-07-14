import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Reads the synced account defaults this device is allowed to browse on.
///
/// The guard is the whole reason this is a use case and not a repository call:
/// what the account asks for and what a *keyless* device may request are two
/// different things. `ForgetApiKey` already drops the defaults with the key, so
/// an explicit default surviving into a keyless app means something went wrong
/// — a crash between the two writes, a hand-edited database — and browse would
/// open on a 401 instead of a grid. This is the second door, closed the same
/// way the NSFW storage rules are.
///
/// ```dart
/// final AccountSettings? defaults = await loadAccountDefaults();
/// ```
class LoadAccountDefaults {
  /// Creates the use case over the settings store and the key store.
  const LoadAccountDefaults({
    required SettingsRepository settings,
    required SecretStore secrets,
  }) : _settings = settings,
       _secrets = secrets;

  final SettingsRepository _settings;
  final SecretStore _secrets;

  /// The stored defaults, stripped of explicit content when no key is stored,
  /// or null when no key has ever been saved. Never throws.
  Future<AccountSettings?> call() async {
    final AccountSettings? stored = await _settings.loadAccountDefaults();
    if (stored == null) return null;
    if (await _secrets.hasApiKey()) return stored;
    return stored.withoutExplicit();
  }
}
