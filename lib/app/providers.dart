import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/network/wallhaven_client.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/secrets/secure_secret_store.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/data/storage/method_channel_image_store.dart';
import 'package:tela/data/wallhaven/dio_wallhaven_api.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_applier.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';
import 'package:tela/domain/use_cases/apply_wallpaper.dart';
import 'package:tela/domain/use_cases/download_wallpaper.dart';
import 'package:tela/domain/use_cases/forget_api_key.dart';
import 'package:tela/domain/use_cases/save_api_key.dart';
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

/// The Android wallpaper port, bound to the native method-channel adapter.
final Provider<WallpaperApplier> wallpaperApplierProvider =
    Provider<WallpaperApplier>(
      (Ref ref) => MethodChannelWallpaperApplier(),
    );

/// The three-tier image-storage port, bound to Android's scoped-storage API.
final Provider<ImageStore> imageStoreProvider = Provider<ImageStore>(
  (Ref ref) => MethodChannelImageStore(),
);

/// tela's SQLite database, opened once and closed with the provider scope.
final Provider<TelaDatabase> telaDatabaseProvider = Provider<TelaDatabase>((
  Ref ref,
) {
  final TelaDatabase db = TelaDatabase.open();
  ref.onDispose(db.close);
  return db;
});

/// The settings port, bound to its Drift adapter.
final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
      (Ref ref) => DriftSettingsRepository(ref.watch(telaDatabaseProvider)),
    );

/// Applies one selected wallpaper to an Android target.
final Provider<ApplyWallpaper> applyWallpaperProvider =
    Provider<ApplyWallpaper>(
      (Ref ref) => ApplyWallpaper(
        applier: ref.watch(wallpaperApplierProvider),
      ),
    );

/// Downloads one wallpaper through the configured storage boundary.
final Provider<DownloadWallpaper> downloadWallpaperProvider =
    Provider<DownloadWallpaper>(
      (Ref ref) => DownloadWallpaper(
        imageStore: ref.watch(imageStoreProvider),
        settings: ref.watch(settingsRepositoryProvider),
      ),
    );

/// The search use case, the only thing the browse feature actually calls.
final Provider<SearchWallpapers> searchWallpapersProvider =
    Provider<SearchWallpapers>(
      (Ref ref) => SearchWallpapers(
        api: ref.watch(wallhavenApiProvider),
        secrets: ref.watch(secretStoreProvider),
      ),
    );

/// Stores an API key, after asking Wallhaven whether it works.
final Provider<SaveApiKey> saveApiKeyProvider = Provider<SaveApiKey>(
  (Ref ref) => SaveApiKey(
    secrets: ref.watch(secretStoreProvider),
    api: ref.watch(wallhavenApiProvider),
  ),
);

/// Drops the stored API key, re-locking NSFW.
final Provider<ForgetApiKey> forgetApiKeyProvider = Provider<ForgetApiKey>(
  (Ref ref) => ForgetApiKey(secrets: ref.watch(secretStoreProvider)),
);
