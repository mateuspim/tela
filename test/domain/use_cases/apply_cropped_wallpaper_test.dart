import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/crop_region.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/use_cases/apply_cropped_wallpaper.dart';

import '../../fakes/fake_wallpaper_applier.dart';

void main() {
  test('forwards the full image, region, and target to the port', () async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    final ApplyCroppedWallpaper apply = ApplyCroppedWallpaper(applier: applier);
    final Wallpaper wallpaper = _wallpaper(Purity.sfw);
    const CropRegion region = CropRegion(
      left: 10,
      top: 20,
      width: 300,
      height: 500,
    );

    await apply(wallpaper, region, WallpaperTarget.both);

    expect(applier.receivedSource, Uri.parse(wallpaper.fullImageUrl));
    expect(applier.receivedRegion, region);
    expect(applier.receivedTarget, WallpaperTarget.both);
    expect(applier.callCount, 1);
  });

  test(
    'applies an explicit wallpaper — the in-app path never exports',
    () async {
      final FakeWallpaperApplier applier = FakeWallpaperApplier();
      final ApplyCroppedWallpaper apply = ApplyCroppedWallpaper(
        applier: applier,
      );

      await apply(
        _wallpaper(Purity.nsfw),
        const CropRegion(left: 0, top: 0, width: 100, height: 100),
        WallpaperTarget.home,
      );

      // Unlike AdjustWallpaper, no ArgumentError: nsfw reaches the port.
      expect(applier.callCount, 1);
      expect(applier.receivedTarget, WallpaperTarget.home);
    },
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
