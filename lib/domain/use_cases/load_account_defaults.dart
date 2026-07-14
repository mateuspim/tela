import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/use_cases/sync_account_defaults.dart';

/// Reads the synced account defaults this device is allowed to browse on, and
/// syncs them the first time it finds a key that never had the chance.
///
/// Two rules live here, and each closes a door the other cannot.
///
/// **The explicit guard.** What an account asks for and what a *keyless* device
/// may request are two different things: an NSFW search with no key is a 401,
/// so browse would open on an error rather than a grid. `ForgetApiKey` already
/// drops the defaults with the key, so an explicit default surviving into a
/// keyless app means something went wrong — a crash between the two writes, a
/// hand-edited database — and this is the second door, closed the way the NSFW
/// storage rules are.
///
/// **The backfill.** `SaveApiKey` syncs, so a key saved *by this build* always
/// has defaults. A key saved by an earlier one does not, and nothing would ever
/// ask again: the feature would silently do nothing for every existing user
/// until they happened to re-paste a key that already works. So a stored key
/// with no stored defaults syncs once, here, and the very next load finds them
/// and spends nothing. Found on the device (2026-07-14), where the settings
/// table had a working key and no `account.*` rows at all.
///
/// ```dart
/// final AccountSettings? defaults = await loadAccountDefaults();
/// ```
class LoadAccountDefaults {
  /// Creates the use case over the settings store, the key store, and the sync
  /// that backfills a key which predates it.
  const LoadAccountDefaults({
    required SettingsRepository settings,
    required SecretStore secrets,
    required SyncAccountDefaults syncDefaults,
  }) : _settings = settings,
       _secrets = secrets,
       _syncDefaults = syncDefaults;

  final SettingsRepository _settings;
  final SecretStore _secrets;
  final SyncAccountDefaults _syncDefaults;

  /// The defaults to browse on, or null when there are none to be had. Never
  /// throws: an account tela cannot reach costs the defaults, not the app.
  Future<AccountSettings?> call() async {
    final AccountSettings? stored = await _settings.loadAccountDefaults();
    if (!await _secrets.hasApiKey()) return stored?.withoutExplicit();
    return stored ?? _backfill();
  }

  /// The one request a key that predates the sync is owed.
  ///
  /// Costs nothing on any later load, because a successful sync writes the rows
  /// this method exists to find. A failure writes nothing and answers null, so
  /// browse opens on tela's own defaults and the next launch may try again —
  /// being offline says nothing about an account, exactly as it says nothing
  /// about a key (`ApiKeySaveOutcome.savedUnverified`).
  Future<AccountSettings?> _backfill() async {
    try {
      return await _syncDefaults();
    } on WallhavenFailure {
      return null;
    }
  }
}
