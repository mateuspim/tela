import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/download_wallpaper.dart';

import '../../fakes/fake_image_store.dart';

void main() {
  test(
    'DownloadWallpaper sends the image, purity, and selected tier to port',
    () async {
      final FakeImageStore imageStore = FakeImageStore();
      final DownloadWallpaper download = DownloadWallpaper(
        imageStore: imageStore,
      );
      final Wallpaper wallpaper = _wallpaper();

      await download(wallpaper, StorageTier.filesOutsideGallery);

      expect(imageStore.receivedId, wallpaper.id);
      expect(imageStore.receivedImageUrl, wallpaper.fullImageUrl);
      expect(imageStore.receivedPurity, Purity.nsfw);
      expect(imageStore.receivedTier, StorageTier.filesOutsideGallery);
    },
  );

  test('StorageTier keeps NSFW private by default', () {
    expect(StorageTier.defaultFor(Purity.sfw), StorageTier.sharedGallery);
    expect(StorageTier.defaultFor(Purity.sketchy), StorageTier.sharedGallery);
    expect(StorageTier.defaultFor(Purity.nsfw), StorageTier.appPrivate);
  });
}

Wallpaper _wallpaper() => const Wallpaper(
  id: 'e7jvjd',
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.nsfw,
  category: Category.general,
  colors: <String>[],
);
