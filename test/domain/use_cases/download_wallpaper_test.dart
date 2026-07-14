import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
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
  });
}

DownloadWallpaper _download(
  FakeImageStore imageStore, {
  StorageSettings? settings,
  FakeDownloadHistory? history,
}) {
  return DownloadWallpaper(
    imageStore: imageStore,
    settings: FakeSettingsRepository(settings: settings),
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
