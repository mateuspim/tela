import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/use_cases/apply_private_image.dart';

import '../../fakes/fake_wallpaper_applier.dart';

void main() {
  test('applies the private file URI to the chosen target', () async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    final ApplyPrivateImage apply = ApplyPrivateImage(applier: applier);

    await apply(_image('e7jvjd'), WallpaperTarget.both);

    // The private file's own location reaches the applier — never a Wallhaven
    // URL. A private image's pixels never travel over the network.
    expect(applier.receivedSources, <Uri>[_location('e7jvjd')]);
    expect(applier.receivedTarget, WallpaperTarget.both);
  });

  test('does not fall back to a network source when the file fails', () async {
    // Unlike ApplyDownload, there is nowhere else to read an explicit file
    // from: a read failure surfaces as a failure and is not retried anywhere.
    final FakeWallpaperApplier applier = FakeWallpaperApplier(
      unreadableSources: <Uri>{_location('e7jvjd')},
    );
    final ApplyPrivateImage apply = ApplyPrivateImage(applier: applier);

    await expectLater(
      apply(_image('e7jvjd'), WallpaperTarget.home),
      throwsA(isA<WallpaperApplyFailure>()),
    );
    expect(applier.callCount, 1);
  });
}

Uri _location(String id) =>
    Uri.file('/data/user/0/cc.pym.tela/files/wallpapers/wallhaven-$id.jpg');

PrivateImage _image(String id) => PrivateImage(
  ref: WallpaperRef(SourceId.wallhaven, id),
  location: _location(id),
  savedAt: DateTime.utc(2026, 7, 14),
  sizeBytes: 2048,
  width: 1080,
  height: 2400,
);
