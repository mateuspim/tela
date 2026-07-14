import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tela/domain/ports/secret_store.dart';

/// [SecretStore] over the Android Keystore, via flutter_secure_storage.
///
/// The only adapter allowed to hold the Wallhaven key. Nothing here logs, and
/// nothing returns the key in an error message.
class SecureSecretStore implements SecretStore {
  /// Creates the store over a configured [FlutterSecureStorage].
  const SecureSecretStore(this._storage);

  /// Creates the store with the plugin's default Android options.
  ///
  /// The defaults are already Keystore-backed (RSA-OAEP key wrapping over
  /// AES-GCM data encryption). Notably we do *not* set
  /// `encryptedSharedPreferences`: it is deprecated in v10 and ignored, because
  /// Google deprecated the Jetpack Security library it was built on.
  factory SecureSecretStore.create() {
    return const SecureSecretStore(FlutterSecureStorage());
  }

  final FlutterSecureStorage _storage;

  static const String _apiKeyEntry = 'wallhaven_api_key';

  @override
  Future<String?> readApiKey() => _storage.read(key: _apiKeyEntry);

  @override
  Future<void> writeApiKey(String apiKey) {
    if (apiKey.isEmpty) {
      throw ArgumentError('api key must be a non-empty string, got ""');
    }
    return _storage.write(key: _apiKeyEntry, value: apiKey);
  }

  @override
  Future<void> deleteApiKey() => _storage.delete(key: _apiKeyEntry);

  @override
  Future<bool> hasApiKey() => _storage.containsKey(key: _apiKeyEntry);
}
