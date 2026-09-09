import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/build_edition.dart';
import 'package:tela/app/configured_download.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/network/konachan_client.dart';
import 'package:tela/core/network/wallhaven_client.dart';
import 'package:tela/data/app/flutter_app_visibility.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_history.dart';
import 'package:tela/data/downloads/drift_download_queue.dart';
import 'package:tela/data/downloads/method_channel_download_queue_anchor.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/data/images/cache_manager_fetched_image_cache.dart';
import 'package:tela/data/images/decoded_dominant_color.dart';
import 'package:tela/data/konachan/dio_konachan_source.dart';
import 'package:tela/data/localsend/beam_identity_store.dart';
import 'package:tela/data/localsend/localsend_beam.dart';
import 'package:tela/data/localsend/method_channel_multicast_lease.dart';
import 'package:tela/data/notifications/method_channel_notification_access.dart';
import 'package:tela/data/secrets/secure_secret_store.dart';
import 'package:tela/data/secrets/unavailable_secret_store.dart';
import 'package:tela/data/security/local_auth_app_lock.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/data/storage/method_channel_image_store.dart';
import 'package:tela/data/storage/method_channel_local_preview_cache.dart';
import 'package:tela/data/storage/method_channel_screen_guard.dart';
import 'package:tela/data/tag_blocklist/drift_tag_blocklist_repository.dart';
import 'package:tela/data/wallhaven/dio_wallhaven_source.dart';
import 'package:tela/data/wallpaper/method_channel_system_wallpaper_editor.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_applier.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_rotation.dart';
import 'package:tela/data/wallpaper/method_channel_wallpaper_sharer.dart';
import 'package:tela/data/wallpaper/url_launcher_external_link.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/app_lock.dart';
import 'package:tela/domain/ports/app_visibility.dart';
import 'package:tela/domain/ports/dominant_color.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/download_queue.dart';
import 'package:tela/domain/ports/download_queue_anchor.dart';
import 'package:tela/domain/ports/external_link.dart';
import 'package:tela/domain/ports/favorites_repository.dart';
import 'package:tela/domain/ports/fetched_image_cache.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';
import 'package:tela/domain/ports/multicast_lease.dart';
import 'package:tela/domain/ports/notification_access.dart';
import 'package:tela/domain/ports/screen_guard.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/ports/system_wallpaper_editor.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';
import 'package:tela/domain/ports/wallpaper_beam.dart';
import 'package:tela/domain/ports/wallpaper_rotation.dart';
import 'package:tela/domain/ports/wallpaper_sharer.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/domain/use_cases/adjust_wallpaper.dart';
import 'package:tela/domain/use_cases/apply_cropped_wallpaper.dart';
import 'package:tela/domain/use_cases/apply_download.dart';
import 'package:tela/domain/use_cases/apply_private_image.dart';
import 'package:tela/domain/use_cases/apply_wallpaper.dart';
import 'package:tela/domain/use_cases/beam_wallpapers.dart';
import 'package:tela/domain/use_cases/browse_collections.dart';
import 'package:tela/domain/use_cases/confirm_nsfw_on_removable.dart';
import 'package:tela/domain/use_cases/delete_download.dart';
import 'package:tela/domain/use_cases/delete_downloads.dart';
import 'package:tela/domain/use_cases/download_wallpaper.dart';
import 'package:tela/domain/use_cases/drain_download_queue.dart';
import 'package:tela/domain/use_cases/forget_api_key.dart';
import 'package:tela/domain/use_cases/load_account_defaults.dart';
import 'package:tela/domain/use_cases/move_stored_images.dart';
import 'package:tela/domain/use_cases/resolve_beam_files.dart';
import 'package:tela/domain/use_cases/resolve_browse_defaults.dart';
import 'package:tela/domain/use_cases/retag_stored_images.dart';
import 'package:tela/domain/use_cases/save_api_key.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';
import 'package:tela/domain/use_cases/share_wallpaper.dart';
import 'package:tela/domain/use_cases/survey_offload_groups.dart';
import 'package:tela/domain/use_cases/sync_account_defaults.dart';
import 'package:tela/domain/use_cases/toggle_favorite.dart';
import 'package:tela/domain/use_cases/walk_listing_pages.dart';

/// The composition root: every port is bound to its adapter exactly once, here.
///
/// Features depend on the ports above, never on the adapters below, so a test
/// swaps an implementation by overriding one provider.

/// Encrypted store for the Wallhaven API key.
final Provider<SecretStore> secretStoreProvider = Provider<SecretStore>(
  (Ref ref) => buildEdition.allowsWallhavenCredentials
      ? SecureSecretStore.create()
      : const UnavailableSecretStore(),
);

/// The configured HTTP client (key header + rate limiting already wired).
final Provider<Dio> wallhavenDioProvider = Provider<Dio>(
  (Ref ref) => WallhavenClient.create(secrets: ref.watch(secretStoreProvider)),
);

/// Wallhaven as a source, bound to its Dio adapter.
///
/// Registered in `wallpaper_sources.dart`; features read the *active* source
/// from there rather than naming this one.
final Provider<WallpaperSource> wallhavenSourceProvider =
    Provider<WallpaperSource>(
      (Ref ref) => DioWallhavenSource(
        ref.watch(wallhavenDioProvider),
        allowExplicit: buildEdition.allowsExplicitContent,
      ),
    );

/// Konachan's HTTP client (User-Agent + rate limiting wired; no key, no base
/// URL — the adapter picks the host per request).
final Provider<Dio> konachanDioProvider = Provider<Dio>(
  (Ref ref) => KonachanClient.create(),
);

/// Konachan as a source, bound to its Dio adapter.
///
/// Registered in `wallpaper_sources.dart`; features read the *active* source
/// from there rather than naming this one.
final Provider<WallpaperSource> konachanSourceProvider =
    Provider<WallpaperSource>(
      (Ref ref) => DioKonachanSource(
        ref.watch(konachanDioProvider),
        allowUnrestricted: buildEdition.allowsUnrestrictedKonachan,
      ),
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

/// Reads the colour an image is mostly made of, for sources that report none.
final Provider<DominantColor> dominantColorProvider = Provider<DominantColor>(
  (Ref ref) => DecodedDominantColor(),
);

/// The screen-protection port, bound to Android's `FLAG_SECURE`.
final Provider<ScreenGuard> screenGuardProvider = Provider<ScreenGuard>(
  (Ref ref) => MethodChannelScreenGuard(),
);

/// The notification-permission port, bound to Android's own settings page.
final Provider<NotificationAccess> notificationAccessProvider =
    Provider<NotificationAccess>(
      (Ref ref) => MethodChannelNotificationAccess(),
    );

/// Whether tela's notifications are on right now.
///
/// autoDispose, because the answer changes **outside this app**: the user
/// leaves for Android's settings page and comes back, and a cached "off" would
/// outlive the switch they just flipped. Re-read whenever the row is rebuilt.
final FutureProvider<bool> notificationsEnabledProvider =
    FutureProvider.autoDispose<bool>(
      (Ref ref) => ref.watch(notificationAccessProvider).areEnabled(),
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

/// The download-queue port, bound to its Drift adapter.
final Provider<DownloadQueue> downloadQueueProvider = Provider<DownloadQueue>(
  (Ref ref) => DriftDownloadQueue(ref.watch(telaDatabaseProvider)),
);

/// The queue's process anchor, bound to Android's foreground service.
final Provider<DownloadQueueAnchor> downloadQueueAnchorProvider =
    Provider<DownloadQueueAnchor>(
      (Ref ref) => MethodChannelDownloadQueueAnchor(),
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
        allowsExplicit: buildEdition.allowsExplicitContent,
      ),
    );

/// A download that runs the device/card chooser the first time the
/// files-outside-gallery tier needs a folder, then retries. See slice 2.
final Provider<ConfiguredDownload> configuredDownloadProvider =
    Provider<ConfiguredDownload>(
      (Ref ref) => ConfiguredDownload(
        perform: (Wallpaper wallpaper, {StorageTier? tier, TagFolder? tag}) =>
            ref.read(downloadWallpaperProvider)(
              wallpaper,
              tier: tier,
              tag: tag,
            ),
        imageStore: ref.watch(imageStoreProvider),
      ),
    );

/// Moves already-downloaded images between storage tiers, without the network.
final Provider<MoveStoredImages> moveStoredImagesProvider =
    Provider<MoveStoredImages>(
      (Ref ref) => MoveStoredImages(
        imageStore: ref.watch(imageStoreProvider),
        history: ref.watch(downloadHistoryProvider),
      ),
    );

/// Whether a screen is in front of the user, for the one storage step that
/// cannot happen without one.
final Provider<AppVisibility> appVisibilityProvider = Provider<AppVisibility>(
  (Ref ref) {
    final FlutterAppVisibility visibility = FlutterAppVisibility();
    ref.onDispose(visibility.dispose);
    return visibility;
  },
);

/// Adds up what sits on built-in storage and could be moved to a card.
final Provider<SurveyOffloadGroups> surveyOffloadGroupsProvider =
    Provider<SurveyOffloadGroups>(
      (Ref ref) => SurveyOffloadGroups(
        imageStore: ref.watch(imageStoreProvider),
        history: ref.watch(downloadHistoryProvider),
      ),
    );

/// Refiles already-downloaded images under another tag, without the network.
final Provider<RetagStoredImages> retagStoredImagesProvider =
    Provider<RetagStoredImages>(
      (Ref ref) => RetagStoredImages(
        imageStore: ref.watch(imageStoreProvider),
        history: ref.watch(downloadHistoryProvider),
        moveStoredImages: ref.watch(moveStoredImagesProvider),
      ),
    );

/// The worker that empties the download queue, several at a time.
///
/// Goes through [downloadWallpaperProvider] and **not**
/// [configuredDownloadProvider]: the latter answers a missing folder by opening
/// the volume chooser, which a worker draining with no screen mounted cannot
/// do. A batch resolves its destination before it enqueues, so the worker marks
/// that case failed instead. See `DrainDownloadQueue`.
final Provider<DrainDownloadQueue> drainDownloadQueueProvider =
    Provider<DrainDownloadQueue>(
      (Ref ref) => DrainDownloadQueue(
        queue: ref.watch(downloadQueueProvider),
        perform: (Wallpaper wallpaper, {StorageTier? tier, TagFolder? tag}) =>
            ref.read(downloadWallpaperProvider)(
              wallpaper,
              tier: tier,
              tag: tag,
            ),
      ),
    );

/// The one-time confirmation before explicit downloads reach a removable card.
/// See slice 4 — enforced at the NSFW tier picker and the folder chooser both.
final Provider<ConfirmNsfwOnRemovable> confirmNsfwOnRemovableProvider =
    Provider<ConfirmNsfwOnRemovable>(
      (Ref ref) =>
          ConfirmNsfwOnRemovable(ref.watch(settingsRepositoryProvider)),
    );

/// Sets an already-downloaded wallpaper again, from the file on this device.
final Provider<ApplyDownload> applyDownloadProvider = Provider<ApplyDownload>(
  (Ref ref) => ApplyDownload(applier: ref.watch(wallpaperApplierProvider)),
);

/// Hard-deletes a download: its file and its history row. One delete path.
final Provider<DeleteDownload> deleteDownloadProvider =
    Provider<DeleteDownload>(
      (Ref ref) => DeleteDownload(
        imageStore: ref.watch(imageStoreProvider),
        history: ref.watch(downloadHistoryProvider),
      ),
    );

/// Hard-deletes a whole selection at once, one system prompt for the gallery.
final Provider<DeleteDownloads> deleteDownloadsProvider =
    Provider<DeleteDownloads>(
      (Ref ref) => DeleteDownloads(
        imageStore: ref.watch(imageStoreProvider),
        history: ref.watch(downloadHistoryProvider),
      ),
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
///
/// Bound to the *active* source, so switching sources rebuilds it and every
/// listing that watches it.
final Provider<SearchWallpapers> searchWallpapersProvider =
    Provider<SearchWallpapers>(
      (Ref ref) => SearchWallpapers(
        source: ref.watch(activeWallpaperSourceProvider),
        secrets: ref.watch(secretStoreProvider),
        blocklist: ref.watch(tagBlocklistRepositoryProvider),
      ),
    );

/// This install's LocalSend identity, generated once and then persisted.
final Provider<BeamIdentityStore> beamIdentityStoreProvider =
    Provider<BeamIdentityStore>(
      (Ref ref) => BeamIdentityStore(ref.watch(settingsRepositoryProvider)),
    );

/// The beam port — LocalSend, over its own Dio.
///
/// **A separate Dio from the wallpaper sources', deliberately.** That one
/// carries the Wallhaven base URL, the API-key interceptor and the 45/min
/// throttle; none of them belong on a LAN transfer, and the key interceptor
/// least of all — it would attach the API key to a request leaving for
/// somebody's desktop.
final Provider<WallpaperBeam> wallpaperBeamProvider = Provider<WallpaperBeam>((
  Ref ref,
) {
  return LocalSendBeam(
    dio: Dio(
      BaseOptions(
        // A receiver waits for a human to tap "accept", so the response can be
        // a long time coming and a short timeout would read as a decline.
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 30),
        // Statuses are read as protocol answers — 403 is a decline, 409 is
        // busy — so they must reach the adapter rather than becoming throws
        // with no response attached.
        validateStatus: (int? status) => status != null && status < 500,
      ),
    ),
    identity: ref.watch(beamIdentityStoreProvider).identity,
  );
});

/// Schedules the platform to change the wallpaper on its own.
///
/// Only ever starts, stops and describes: the rotation itself runs natively
/// with no Dart alive (see `WallpaperRotationWorker`).
final Provider<WallpaperRotation> wallpaperRotationProvider =
    Provider<WallpaperRotation>(
      (Ref ref) => const MethodChannelWallpaperRotation(),
    );

/// Resolves stored images into files a beam can read.
///
/// Bound to the preview cache because a vault image's SAF URI is the whole
/// reason it exists — see [ResolveBeamFiles].
final Provider<ResolveBeamFiles> resolveBeamFilesProvider =
    Provider<ResolveBeamFiles>(
      (Ref ref) => ResolveBeamFiles(ref.watch(localPreviewCacheProvider)),
    );

/// Keeps the device able to receive multicast while a discovery is open.
final Provider<MulticastLease> multicastLeaseProvider =
    Provider<MulticastLease>((Ref ref) => const MethodChannelMulticastLease());

/// Sends wallpapers to a machine on the LAN, under the explicit-beam gate.
final Provider<BeamWallpapers> beamWallpapersProvider =
    Provider<BeamWallpapers>(
      (Ref ref) => BeamWallpapers(
        beam: ref.watch(wallpaperBeamProvider),
        settings: ref.watch(settingsRepositoryProvider),
        lease: ref.watch(multicastLeaseProvider),
      ),
    );

/// Reads collections on the active source.
///
/// Bound to the active source like [searchWallpapersProvider], not pinned to
/// Wallhaven: collections are a capability any source may grow, and the use
/// case refuses on one that has not (`SourceCapabilities.browsesCollections`).
final Provider<BrowseCollections> browseCollectionsProvider =
    Provider<BrowseCollections>(
      (Ref ref) => BrowseCollections(
        source: ref.watch(activeWallpaperSourceProvider),
        secrets: ref.watch(secretStoreProvider),
        settings: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Walks a whole listing page by page, for a bulk download.
final Provider<WalkListingPages> walkListingPagesProvider =
    Provider<WalkListingPages>(
      (Ref ref) =>
          WalkListingPages(search: ref.watch(searchWallpapersProvider)),
    );

/// Pulls the Wallhaven account's browse defaults and stores them.
///
/// Bound to Wallhaven itself rather than the active source, and deliberately:
/// these are *that account's* defaults, and Wallhaven is the only source that
/// declares `syncsAccountDefaults`. Browsing Konachan does not make a
/// Wallhaven account's settings stale.
final Provider<SyncAccountDefaults> syncAccountDefaultsProvider =
    Provider<SyncAccountDefaults>(
      (Ref ref) => SyncAccountDefaults(
        source: ref.watch(wallhavenSourceProvider),
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
