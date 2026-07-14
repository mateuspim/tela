import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/use_cases/apply_wallpaper.dart';

import '../../fakes/fake_wallpaper_applier.dart';

void main() {
  test('ApplyWallpaper sends the full image and target to the port', () async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    final ApplyWallpaper apply = ApplyWallpaper(applier: applier);
    final Wallpaper wallpaper = _wallpaper();

    await apply(wallpaper, WallpaperTarget.lock);

    expect(applier.receivedSource, Uri.parse(wallpaper.fullImageUrl));
    expect(applier.receivedTarget, WallpaperTarget.lock);
    expect(applier.callCount, 1);
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
  purity: Purity.sfw,
  category: Category.general,
  colors: <String>[],
);
