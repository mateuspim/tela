import 'package:tela/domain/ports/secret_store.dart';

/// A credential port for editions that do not support credentials.
///
/// Reads behave like a fresh install. A write fails explicitly so a future
/// entry point cannot accidentally turn a clean edition into a credentialed
/// one merely because its UI gate was missed.
class UnavailableSecretStore implements SecretStore {
  /// Creates the stateless clean-edition store.
  const UnavailableSecretStore();

  @override
  Future<void> deleteApiKey() async {}

  @override
  Future<bool> hasApiKey() async => false;

  @override
  Future<String?> readApiKey() async => null;

  @override
  Future<void> writeApiKey(String apiKey) {
    throw UnsupportedError(
      'Wallhaven credentials are unavailable in this build edition',
    );
  }
}
