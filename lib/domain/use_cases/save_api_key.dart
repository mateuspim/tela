import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';

/// What became of a key that [SaveApiKey] accepted.
///
/// A rejected key is not an outcome — it throws [InvalidApiKeyFailure], and
/// nothing is left stored.
enum ApiKeySaveOutcome {
  /// Wallhaven served an NSFW listing with the key. It works.
  verified,

  /// The key is stored, but Wallhaven could not be reached to confirm it.
  savedUnverified,
}

/// Stores a Wallhaven API key, after checking that Wallhaven accepts it.
///
/// The check is an NSFW-purity search: it is the cheapest request that *must*
/// 401 for a bad key, so it proves the key without pulling Wave 2's
/// `GET /settings` account endpoint into [WallhavenApi] early. It spends one of
/// the 45 req/min.
///
/// ```dart
/// final ApiKeySaveOutcome outcome = await saveApiKey(pastedKey);
/// ```
class SaveApiKey {
  /// Creates the use case over the key store and the API that validates it.
  const SaveApiKey({
    required SecretStore secrets,
    required WallhavenApi api,
  }) : _secrets = secrets,
       _api = api;

  final SecretStore _secrets;
  final WallhavenApi _api;

  /// The probe: one page of explicit wallpapers, which Wallhaven serves only to
  /// a valid key.
  static const SearchQuery _nsfwProbe = SearchQuery(
    purity: PurityFilter(<Purity>{Purity.nsfw}),
  );

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
      await _api.search(_nsfwProbe);
      return ApiKeySaveOutcome.verified;
    } on InvalidApiKeyFailure {
      await _restore(previous);
      rethrow;
    } on WallhavenFailure {
      // Offline or rate-limited says nothing about the key. Keeping it beats
      // making the user re-paste it when their connection comes back.
      return ApiKeySaveOutcome.savedUnverified;
    }
  }

  Future<void> _restore(String? previous) {
    if (previous == null) return _secrets.deleteApiKey();
    return _secrets.writeApiKey(previous);
  }
}
