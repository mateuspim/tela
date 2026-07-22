import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/configured_download.dart';
import 'package:tela/core/network/wallhaven_client.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_history.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/data/images/cache_manager_fetched_image_cache.dart';
import 'package:tela/data/secrets/secure_secret_store.dart';
import 'package:tela/data/security/local_auth_app_lock.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/data/storage/method_channel_image_store.dart';
import 'package:tela/data/storage/method_channel_local_preview_cache.dart';
import 'package:tela/data/storage/method_channel_screen_guard.dart';
import 'package:tela/data/tag_blocklist/drift_tag_blocklist_repository.dart';
import 'package:tela/data/wallhaven/dio_wallhaven_api.dart';
import 'package:tela/data/wallpaper/method_channel_system_wallpaper_editor.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_applier.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_sharer.dart';
import 'package:tela/data/wallpaper/url_launcher_external_link.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/app_lock.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/external_link.dart';
import 'package:tela/domain/ports/favorites_repository.dart';
import 'package:tela/domain/ports/fetched_image_cache.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';
import 'package:tela/domain/ports/screen_guard.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/ports/system_wallpaper_editor.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';
import 'package:tela/domain/ports/wallpaper_sharer.dart';
import 'package:tela/domain/use_cases/adjust_wallpaper.dart';
import 'package:tela/domain/use_cases/apply_cropped_wallpaper.dart';
import 'package:tela/domain/use_cases/apply_download.dart';
import 'package:tela/domain/use_cases/apply_private_image.dart';
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

/// The system-editor port, bound to Android's own crop-and-set activity.
final Provider<SystemWallpaperEditor> systemWallpaperEditorProvider =
    Provider<SystemWallpaperEditor>(
      (Ref ref) => MethodChannelSystemWallpaperEditor(),
    );

/// The external-link port, bound to the device browser via `url_launcher`.
final Provider<ExternalLink> externalLinkProvider = Provider<ExternalLink>(
  (Ref ref) => const UrlLauncherExternalLink(),
);

/// The three-tier image-storage port, bound to Android's scoped-storage API.
final Provider<ImageStore> imageStoreProvider = Provider<ImageStore>(
  (Ref ref) => MethodChannelImageStore(),
);

/// The local-preview port, bound to native materialisation of a download's
/// `content:`/SAF location into a decodable cache file.
final Provider<LocalPreviewCache> localPreviewCacheProvider =
    Provider<LocalPreviewCache>(
      (Ref ref) => MethodChannelLocalPreviewCache(),
    );

/// The fetched-image disk cache, as Settings can measure and empty it.
final Provider<FetchedImageCache> fetchedImageCacheProvider =
    Provider<FetchedImageCache>(
      (Ref ref) => CacheManagerFetchedImageCache(),
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
///
/// **Has no default, deliberately**: `main.dart` is the one place that binds
/// it, with [openTelaDatabase]. Opening the real database here read as the
/// obvious default and was a trap. Any widget test mounting anything reaching a
/// Drift-backed port would silently get the real one — and that is most of
/// them, since `WallpaperGrid` listens to the blocklist for its re-filter.
///
/// The failure never named a database. `TelaDatabase.open()` resolves its path
/// through path_provider, which answers no plugin under `flutter test`, and
/// lazily — so the provider *constructed* fine and the error surfaced later and
/// elsewhere, as an `AsyncError` inside `blockedTagsProvider` that the grid's
/// own change-gate reads as "no value yet" and correctly ignores. What the
/// author saw was an empty grid, and a `RangeError` from tapping a tile that
/// was never there. It cost two harnesses, one of them the cold-launch hang's
/// own regression test.
///
/// Unbound now throws, by name, at the moment of the read.
final Provider<TelaDatabase> telaDatabaseProvider = Provider<TelaDatabase>((
  Ref ref,
) {
  throw UnimplementedError(
    'telaDatabaseProvider has no default and must be overridden. '
    'Production binds it in main.dart: '
    'telaDatabaseProvider.overrideWith(openTelaDatabase). '
    'A test should instead override the Drift-backed port it actually needs '
    '(settingsRepositoryProvider, favoritesRepositoryProvider, '
    'downloadHistoryProvider or tagBlocklistRepositoryProvider) with its fake.',
  );
});

/// Opens the real database and closes it with the scope: the production binding
/// for [telaDatabaseProvider], applied once in `main.dart`.
///
/// Lives here beside the ports it feeds rather than in `main.dart`, so the
/// wiring stays in the one file that knows which adapter every port gets.
///
/// ```dart
/// ProviderContainer(
///   overrides: <Override>[
///     telaDatabaseProvider.overrideWith(openTelaDatabase),
///   ],
/// );
/// ```
TelaDatabase openTelaDatabase(Ref ref) {
  final TelaDatabase db = TelaDatabase.open();
  ref.onDispose(db.close);
  return db;
}

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

/// A download that runs the device/card chooser the first time the
/// files-outside-gallery tier needs a folder, then retries. See slice 2.
final Provider<ConfiguredDownload> configuredDownloadProvider =
    Provider<ConfiguredDownload>(
      (Ref ref) => ConfiguredDownload(
        perform: (Wallpaper wallpaper, {StorageTier? tier}) =>
            ref.read(downloadWallpaperProvider)(wallpaper, tier: tier),
        imageStore: ref.watch(imageStoreProvider),
      ),
    );

/// Sets an already-downloaded wallpaper again, from the file on this device.
final Provider<ApplyDownload> applyDownloadProvider = Provider<ApplyDownload>(
  (Ref ref) => ApplyDownload(applier: ref.watch(wallpaperApplierProvider)),
);

/// Sets an app-private wallpaper, from the file only tela can open.
final Provider<ApplyPrivateImage> applyPrivateImageProvider =
    Provider<ApplyPrivateImage>(
      (Ref ref) =>
          ApplyPrivateImage(applier: ref.watch(wallpaperApplierProvider)),
    );

/// Shares one wallpaper out — its Wallhaven link, or the image file itself.
final Provider<ShareWallpaper> shareWallpaperProvider =
    Provider<ShareWallpaper>(
      (Ref ref) => ShareWallpaper(sharer: ref.watch(wallpaperSharerProvider)),
    );

/// Opens one wallpaper in Android's own editor, to frame before setting.
final Provider<AdjustWallpaper> adjustWallpaperProvider =
    Provider<AdjustWallpaper>(
      (Ref ref) =>
          AdjustWallpaper(editor: ref.watch(systemWallpaperEditorProvider)),
    );

/// Applies a crop the user framed in tela's own editor — the in-app path that,
/// unlike [adjustWallpaperProvider], keeps explicit pixels inside the app.
final Provider<ApplyCroppedWallpaper> applyCroppedWallpaperProvider =
    Provider<ApplyCroppedWallpaper>(
      (Ref ref) =>
          ApplyCroppedWallpaper(applier: ref.watch(wallpaperApplierProvider)),
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
