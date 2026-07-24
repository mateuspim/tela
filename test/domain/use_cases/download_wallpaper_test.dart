import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/download_wallpaper.dart';

import '../../fakes/fake_download_history.dart';
import '../../fakes/fake_image_store.dart';
import '../../fakes/fake_settings_repository.dart';

void main() {
  group('DownloadWallpaper', () {
    test('sends the image, purity, and overridden tier to the port', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final DownloadWallpaper download = _download(imageStore);
      final Wallpaper wallpaper = _wallpaper(Purity.nsfw);

      await download(wallpaper, tier: StorageTier.filesOutsideGallery);

      expect(imageStore.receivedId, wallpaper.id);
      expect(imageStore.receivedImageUrl, wallpaper.fullImageUrl);
      expect(imageStore.receivedPurity, Purity.nsfw);
      expect(imageStore.receivedTier, StorageTier.filesOutsideGallery);
    });

    test(
      'routes to the tier configured for the purity when not told',
      () async {
        final FakeImageStore imageStore = FakeImageStore();
        final DownloadWallpaper download = _download(
          imageStore,
          settings: StorageSettings(
            sfwTier: StorageTier.filesOutsideGallery,
            nsfwTier: StorageTier.appPrivate,
          ),
        );

        await download(_wallpaper(Purity.sfw));
        expect(imageStore.receivedTier, StorageTier.filesOutsideGallery);

        await download(_wallpaper(Purity.nsfw));
        expect(imageStore.receivedTier, StorageTier.appPrivate);
      },
    );

    test('keeps explicit downloads out of the gallery by default', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final DownloadWallpaper download = _download(imageStore);

      await download(_wallpaper(Purity.nsfw));

      expect(imageStore.receivedTier, StorageTier.appPrivate);
    });

    test('records where the download landed, so it can be set again', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory();
      final DownloadWallpaper download = _download(
        imageStore,
        history: history,
      );
      final Wallpaper wallpaper = _wallpaper(Purity.sfw);

      await download(wallpaper, tier: StorageTier.filesOutsideGallery);

      final DownloadRecord recorded = history.recorded.single;
      expect(recorded.wallpaper, wallpaper);
      // The tier the store *answered* with, not the one that was asked for: the
      // record has to name where the file actually is.
      expect(recorded.tier, StorageTier.filesOutsideGallery);
      expect(recorded.location, Uri.parse('memory://${wallpaper.id}'));
    });

    test('never records an explicit download, in any tier', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory();
      final DownloadWallpaper download = _download(
        imageStore,
        history: history,
      );

      await download(_wallpaper(Purity.nsfw));
      await download(
        _wallpaper(Purity.nsfw),
        tier: StorageTier.filesOutsideGallery,
      );

      // The file is stored; only the browsable, backed-up row is withheld.
      expect(imageStore.receivedTier, StorageTier.filesOutsideGallery);
      expect(history.recorded, isEmpty);
    });

    // The rule is the destination, not the wallpaper. A safe wallpaper sent to
    // the private tier was sent there to be private, and the private library is
    // already that tier's index; a history row would be the ungated, backed-up
    // one the tier exists to prevent.
    test(
      'never records a download to the private tier, whatever its purity',
      () async {
        for (final Purity purity in <Purity>[Purity.sfw, Purity.sketchy]) {
          final FakeImageStore imageStore = FakeImageStore();
          final FakeDownloadHistory history = FakeDownloadHistory();
          final DownloadWallpaper download = _download(
            imageStore,
            history: history,
          );

          await download(_wallpaper(purity), tier: StorageTier.appPrivate);

          expect(
            imageStore.receivedTier,
            StorageTier.appPrivate,
            reason: 'the file itself is still stored, as asked',
          );
          expect(
            history.recorded,
            isEmpty,
            reason: '$purity to appPrivate must earn no history row',
          );
        }
      },
    );

    test('still records a safe download to the gallery', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory();
      final DownloadWallpaper download = _download(
        imageStore,
        history: history,
      );

      await download(_wallpaper(Purity.sfw), tier: StorageTier.sharedGallery);

      // The rule above must not have quietly emptied History altogether.
      expect(history.recorded.single.tier, StorageTier.sharedGallery);
    });
  });

  group('the destination memory', () {
    // The case that decides the whole design. History drops explicit and
    // private downloads on purpose, which is exactly the run the memory exists
    // to notice — so the memory cannot be built on History, and this is the
    // test that fails first if someone tries.
    test('counts the very downloads the history refuses to keep', () async {
      final FakeDownloadHistory history = FakeDownloadHistory();
      final FakeSettingsRepository repository = FakeSettingsRepository();
      final DownloadWallpaper download = _download(
        FakeImageStore(),
        history: history,
        repository: repository,
      );

      await download(_wallpaper(Purity.nsfw), tier: StorageTier.appPrivate);
      await download(_wallpaper(Purity.nsfw), tier: StorageTier.appPrivate);

      expect(history.recorded, isEmpty);
      expect(repository.streakSaved(Purity.nsfw)?.length, 2);
    });

    test('restarts the run when a download lands somewhere else', () async {
      final FakeSettingsRepository repository = FakeSettingsRepository();
      final DownloadWallpaper download = _download(
        FakeImageStore(),
        repository: repository,
      );

      await download(_wallpaper(Purity.sfw), tier: StorageTier.appPrivate);
      await download(_wallpaper(Purity.sfw), tier: StorageTier.sharedGallery);

      final DownloadDestinationStreak? streak = repository.streakSaved(
        Purity.sfw,
      );
      expect(streak?.tier, StorageTier.sharedGallery);
      expect(streak?.length, 1);
    });

    // The adapter has the last word on where a file went — G's decline
    // behaviour reroutes explicit downloads to the private tier — so a memory
    // built on the *requested* tier would remember a destination that was
    // never used.
    test('remembers where the file landed, not what was asked for', () async {
      final FakeSettingsRepository repository = FakeSettingsRepository();
      final FakeImageStore imageStore = FakeImageStore(
        storedImage: StoredImage(
          location: Uri.parse('memory://rerouted'),
          tier: StorageTier.appPrivate,
        ),
      );

      await _download(imageStore, repository: repository)(
        _wallpaper(Purity.nsfw),
        tier: StorageTier.filesOutsideGallery,
      );

      expect(repository.streakSaved(Purity.nsfw)?.tier, StorageTier.appPrivate);
    });
  });

  group('the "Keep sending here" pin', () {
    test('a plain download goes to the pin, not the configured tier', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final DownloadWallpaper download = _download(
        imageStore,
        repository: FakeSettingsRepository(
          settings: StorageSettings.defaults, // sfw → gallery
          pinnedDownloadTier: StorageTier.filesOutsideGallery,
        ),
      );

      await download(_wallpaper(Purity.sfw));

      expect(imageStore.receivedTier, StorageTier.filesOutsideGallery);
    });

    test('lets a per-download tier win over the pin', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final DownloadWallpaper download = _download(
        imageStore,
        repository: FakeSettingsRepository(
          pinnedDownloadTier: StorageTier.appPrivate,
        ),
      );

      await download(_wallpaper(Purity.sfw), tier: StorageTier.sharedGallery);

      expect(imageStore.receivedTier, StorageTier.sharedGallery);
    });

    // The invariant, surfaced one layer up: a gallery pin is legal to hold, but
    // it can never carry an explicit download into the MediaStore-indexed tier.
    test('an explicit download under a gallery pin falls to private', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final DownloadWallpaper download = _download(
        imageStore,
        repository: FakeSettingsRepository(
          settings: StorageSettings.defaults, // nsfw → appPrivate
          pinnedDownloadTier: StorageTier.sharedGallery,
        ),
      );

      await download(_wallpaper(Purity.nsfw));

      expect(imageStore.receivedTier, StorageTier.appPrivate);
    });

    test('still sends sketchy and safe downloads to a gallery pin', () async {
      for (final Purity purity in <Purity>[Purity.sfw, Purity.sketchy]) {
        final FakeImageStore imageStore = FakeImageStore();
        final DownloadWallpaper download = _download(
          imageStore,
          repository: FakeSettingsRepository(
            settings: StorageSettings(
              sfwTier: StorageTier.appPrivate,
              nsfwTier: StorageTier.appPrivate,
            ),
            pinnedDownloadTier: StorageTier.sharedGallery,
          ),
        );

        await download(_wallpaper(purity));

        expect(
          imageStore.receivedTier,
          StorageTier.sharedGallery,
          reason: '$purity is legal for the gallery, so the pin governs it',
        );
      }
    });
  });
}

DownloadWallpaper _download(
  FakeImageStore imageStore, {
  StorageSettings? settings,
  FakeDownloadHistory? history,
  FakeSettingsRepository? repository,
}) {
  return DownloadWallpaper(
    imageStore: imageStore,
    settings: repository ?? FakeSettingsRepository(settings: settings),
    history: history ?? FakeDownloadHistory(),
  );
}

Wallpaper _wallpaper(Purity purity) => Wallpaper(
  id: 'e7jvjd',
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
