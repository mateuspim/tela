import 'package:tela/domain/ports/secret_store.dart';

/// Removes the stored Wallhaven API key.
///
/// NSFW becomes unreachable again the moment this returns: `SearchWallpapers`
/// refuses an explicit query with no key, and the settings screen stops
/// offering the NSFW purity.
///
/// ```dart
/// await forgetApiKey();
/// ```
class ForgetApiKey {
  /// Creates the use case over the key store.
  const ForgetApiKey({required SecretStore secrets}) : _secrets = secrets;

  final SecretStore _secrets;

  /// Deletes the key. Deleting when none is stored is not an error.
  Future<void> call() => _secrets.deleteApiKey();
}
