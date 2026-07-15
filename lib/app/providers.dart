import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/network/wallhaven_client.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_history.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/data/secrets/secure_secret_store.dart';
import 'package:tela/data/security/local_auth_app_lock.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/data/storage/method_channel_image_store.dart';
import 'package:tela/data/storage/method_channel_screen_guard.dart';
import 'package:tela/data/tag_blocklist/drift_tag_blocklist_repository.dart';
import 'package:tela/data/wallhaven/dio_wallhaven_api.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_applier.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_sharer.dart';
import 'package:tela/domain/ports/app_lock.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/favorites_repository.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/domain/ports/screen_guard.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';
import 'package:tela/domain/ports/wallpaper_sharer.dart';
import 'package:tela/domain/use_cases/apply_download.dart';
import 'package:tela/domain/use_cases/apply_wallpaper.dart';
import 'package:tela/domain/use_cases/download_wallpaper.dart';
import 'package:tela/domain/use_cases/forget_api_key.dart';
import 'package:tela/domain/use_cases/load_account_defaults.dart';
import 'package:tela/domain/use_cases/resolve_browse_defaults.dart';
import 'package:tela/domain/use_cases/save_api_key.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';
import 'package:tela/domain/use_cases/share_wallpaper.dart';
import 'package:tela/domain/use_cases/sync_account_defaults.dart';
import 'package:tela/domain/use_cases/toggle_favorite.dart';

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

/// The share port, bound to the native Android share-sheet adapter.
final Provider<WallpaperSharer> wallpaperSharerProvider =
    Provider<WallpaperSharer>(
      (Ref ref) => MethodChannelWallpaperSharer(),
    );

/// The three-tier image-storage port, bound to Android's scoped-storage API.
final Provider<ImageStore> imageStoreProvider = Provider<ImageStore>(
  (Ref ref) => MethodChannelImageStore(),
);

/// The screen-protection port, bound to Android's `FLAG_SECURE`.
final Provider<ScreenGuard> screenGuardProvider = Provider<ScreenGuard>(
  (Ref ref) => MethodChannelScreenGuard(),
);

/// The app-lock port, bound to Android's BiometricPrompt.
final Provider<AppLock> appLockProvider = Provider<AppLock>(
  (Ref ref) => LocalAuthAppLock(),
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

/// The favorites port, bound to its Drift adapter.
final Provider<FavoritesRepository> favoritesRepositoryProvider =
    Provider<FavoritesRepository>(
      (Ref ref) => DriftFavoritesRepository(ref.watch(telaDatabaseProvider)),
    );

/// The download-history port, bound to its Drift adapter.
final Provider<DownloadHistory> downloadHistoryProvider =
    Provider<DownloadHistory>(
      (Ref ref) => DriftDownloadHistory(ref.watch(telaDatabaseProvider)),
    );

/// The tag-blocklist port, bound to its Drift adapter.
final Provider<TagBlocklistRepository> tagBlocklistRepositoryProvider =
    Provider<TagBlocklistRepository>(
      (Ref ref) => DriftTagBlocklistRepository(ref.watch(telaDatabaseProvider)),
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
        history: ref.watch(downloadHistoryProvider),
      ),
    );

/// Sets an already-downloaded wallpaper again, from the file on this device.
final Provider<ApplyDownload> applyDownloadProvider = Provider<ApplyDownload>(
  (Ref ref) => ApplyDownload(applier: ref.watch(wallpaperApplierProvider)),
);

/// Shares one wallpaper out — its Wallhaven link, or the image file itself.
final Provider<ShareWallpaper> shareWallpaperProvider =
    Provider<ShareWallpaper>(
      (Ref ref) => ShareWallpaper(sharer: ref.watch(wallpaperSharerProvider)),
    );

/// The search use case, the only thing the browse feature actually calls.
final Provider<SearchWallpapers> searchWallpapersProvider =
    Provider<SearchWallpapers>(
      (Ref ref) => SearchWallpapers(
        api: ref.watch(wallhavenApiProvider),
        secrets: ref.watch(secretStoreProvider),
        blocklist: ref.watch(tagBlocklistRepositoryProvider),
      ),
    );

/// Pulls the Wallhaven account's browse defaults and stores them.
final Provider<SyncAccountDefaults> syncAccountDefaultsProvider =
    Provider<SyncAccountDefaults>(
      (Ref ref) => SyncAccountDefaults(
        api: ref.watch(wallhavenApiProvider),
        settings: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Reads back the synced defaults this device may actually browse on.
final Provider<LoadAccountDefaults> loadAccountDefaultsProvider =
    Provider<LoadAccountDefaults>(
      (Ref ref) => LoadAccountDefaults(
        settings: ref.watch(settingsRepositoryProvider),
        secrets: ref.watch(secretStoreProvider),
        syncDefaults: ref.watch(syncAccountDefaultsProvider),
      ),
    );

/// Picks the defaults browse actually opens on, from the source the user chose.
final Provider<ResolveBrowseDefaults> resolveBrowseDefaultsProvider =
    Provider<ResolveBrowseDefaults>(
      (Ref ref) => ResolveBrowseDefaults(
        settings: ref.watch(settingsRepositoryProvider),
        loadAccount: ref.watch(loadAccountDefaultsProvider),
      ),
    );

/// Stores an API key, after asking Wallhaven whether it works.
final Provider<SaveApiKey> saveApiKeyProvider = Provider<SaveApiKey>(
  (Ref ref) => SaveApiKey(
    secrets: ref.watch(secretStoreProvider),
    syncDefaults: ref.watch(syncAccountDefaultsProvider),
  ),
);

/// Drops the stored API key and the account defaults it unlocked, re-locking
/// NSFW.
final Provider<ForgetApiKey> forgetApiKeyProvider = Provider<ForgetApiKey>(
  (Ref ref) => ForgetApiKey(
    secrets: ref.watch(secretStoreProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// Keeps or drops one wallpaper from the local favorites.
final Provider<ToggleFavorite> toggleFavoriteProvider =
    Provider<ToggleFavorite>(
      (Ref ref) =>
          ToggleFavorite(favorites: ref.watch(favoritesRepositoryProvider)),
    );
