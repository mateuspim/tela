import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/network/wallhaven_client.dart';
import 'package:tela/data/secrets/secure_secret_store.dart';
import 'package:tela/data/wallhaven/dio_wallhaven_api.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';

/// The composition root: every port is bound to its adapter exactly once, here.
///
/// Features depend on the ports above, never on the adapters below, so a test
/// swaps an implementation by overriding one provider.

/// Encrypted store for the Wallhaven API key.
final Provider<SecretStore> secretStoreProvider = Provider<SecretStore>(
  (Ref ref) => SecureSecretStore.create(),
);

/// The configured HTTP client (key header + rate limiting already wired).
final Provider<Dio> wallhavenDioProvider = Provider<Dio>(
  (Ref ref) => WallhavenClient.create(secrets: ref.watch(secretStoreProvider)),
);

/// The Wallhaven port, bound to its Dio adapter.
final Provider<WallhavenApi> wallhavenApiProvider = Provider<WallhavenApi>(
  (Ref ref) => DioWallhavenApi(ref.watch(wallhavenDioProvider)),
);

/// The search use case, the only thing the browse feature actually calls.
final Provider<SearchWallpapers> searchWallpapersProvider =
    Provider<SearchWallpapers>(
      (Ref ref) => SearchWallpapers(
        api: ref.watch(wallhavenApiProvider),
        secrets: ref.watch(secretStoreProvider),
      ),
    );
