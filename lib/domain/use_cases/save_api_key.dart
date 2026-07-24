import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/use_cases/sync_account_defaults.dart';

/// What became of a key that [SaveApiKey] accepted.
///
/// A rejected key is not an outcome — it throws [InvalidApiKeyFailure], and
/// nothing is left stored.
enum ApiKeySaveOutcome {
  /// Wallhaven served the account's settings with the key. It works, and its
  /// browse defaults are now this device's.
  verified,

  /// The key is stored, but Wallhaven could not be reached to confirm it. The
  /// account's defaults are not known, so tela's own still apply.
  savedUnverified,
}

/// Stores a Wallhaven API key, after checking that Wallhaven accepts it.
///
/// The check is [SyncAccountDefaults] — `GET /settings`, which serves nobody
/// without a key. It replaced an NSFW-purity search that proved the same thing:
/// this one costs the same single request out of the 45/min but *answers* with
/// something (the account's browse defaults), instead of fetching a page of
/// explicit imagery only to throw it away.
///
/// ```dart
/// final ApiKeySaveOutcome outcome = await saveApiKey(pastedKey);
/// ```
class SaveApiKey {
  /// Creates the use case over the key store and the sync that validates it.
  const SaveApiKey({
    required SecretStore secrets,
    required SyncAccountDefaults syncDefaults,
  }) : _secrets = secrets,
       _syncDefaults = syncDefaults;

  final SecretStore _secrets;
  final SyncAccountDefaults _syncDefaults;

  /// Trims and stores [apiKey], then verifies it.
  ///
  /// Throws [ArgumentError] if [apiKey] is blank, and [InvalidApiKeyFailure] if
  /// Wallhaven rejects it — in which case any previously working key is put
  /// back, so a typo while editing a good key does not cost the user the good
  /// key.
  Future<ApiKeySaveOutcome> call(String apiKey) async {
    final String key = apiKey.trim();
    if (key.isEmpty) {
      throw ArgumentError('api key must be a non-blank string, got "$apiKey"');
    }

    // Store first: the key reaches the request through the store, via
    // ApiKeyInterceptor. There is no way to send a key that isn't stored yet.
    final String? previous = await _secrets.readApiKey();
    await _secrets.writeApiKey(key);
    return _verify(previous);
  }

  Future<ApiKeySaveOutcome> _verify(String? previous) async {
    try {
      await _syncDefaults();
      return ApiKeySaveOutcome.verified;
    } on InvalidApiKeyFailure {
      await _restore(previous);
      rethrow;
    } on SourceFailure {
      // Offline or rate-limited says nothing about the key. Keeping it beats
      // making the user re-paste it when their connection comes back. The
      // defaults stay unsynced; nothing was written, so nothing is half-right.
      return ApiKeySaveOutcome.savedUnverified;
    }
  }

  Future<void> _restore(String? previous) {
    if (previous == null) return _secrets.deleteApiKey();
    return _secrets.writeApiKey(previous);
  }
}
