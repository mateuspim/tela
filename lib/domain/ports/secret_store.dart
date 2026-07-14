/// Encrypted-at-rest storage for the one secret this app has: the Wallhaven
/// API key.
///
/// Implemented in `data/` over flutter_secure_storage. Nothing else in the app
/// may hold the key in plain state, and it is never logged (CLAUDE.md).
///
/// ```dart
/// if (await secrets.hasApiKey()) { /* nsfw is unlockable */ }
/// ```
abstract interface class SecretStore {
  /// Reads the stored Wallhaven API key, or null if the user never set one.
  Future<String?> readApiKey();

  /// Stores [apiKey], replacing any existing one.
  Future<void> writeApiKey(String apiKey);

  /// Removes the stored key. NSFW becomes unavailable again.
  Future<void> deleteApiKey();

  /// Whether a key is stored. Cheaper than [readApiKey] at call sites that only
  /// need to know whether to *offer* NSFW, and it avoids pulling the secret
  /// into memory just to null-check it.
  Future<bool> hasApiKey();
}
