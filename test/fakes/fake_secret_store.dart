import 'package:tela/domain/ports/secret_store.dart';

/// In-memory [SecretStore]. Starts empty, i.e. NSFW locked.
class FakeSecretStore implements SecretStore {
  /// Creates a store, optionally pre-seeded with a key.
  FakeSecretStore({this.storedKey});

  /// The key currently held, or null when NSFW is locked.
  String? storedKey;

  @override
  Future<String?> readApiKey() async => storedKey;

  @override
  Future<void> writeApiKey(String apiKey) async => storedKey = apiKey;

  @override
  Future<void> deleteApiKey() async => storedKey = null;

  @override
  Future<bool> hasApiKey() async => storedKey != null;
}
