import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/use_cases/apply_download.dart';

import '../../fakes/fake_wallpaper_applier.dart';

void main() {
  group('ApplyDownload', () {
    test(
      'sets the file on this device, not the wallpaper on Wallhaven',
      () async {
        final FakeWallpaperApplier applier = FakeWallpaperApplier();
        final ApplyDownload apply = ApplyDownload(applier: applier);

        await apply(_download(), WallpaperTarget.both);

        expect(applier.receivedSources, <Uri>[_location]);
        expect(applier.receivedTarget, WallpaperTarget.both);
      },
    );

    test('falls back to Wallhaven when the local file is gone', () async {
      final FakeWallpaperApplier applier = FakeWallpaperApplier(
        unreadableSources: <Uri>{_location},
      );
      final ApplyDownload apply = ApplyDownload(applier: applier);
      final DownloadRecord download = _download();

      await apply(download, WallpaperTarget.home);

      // The file was deleted from Photos behind tela's back; the row still
      // knows where it came from, so that costs a re-fetch, not the feature.
      expect(applier.receivedSources, <Uri>[
        _location,
        Uri.parse(download.wallpaper.fullImageUrl),
      ]);
      expect(applier.receivedTarget, WallpaperTarget.home);
    });

    test('does not re-download a wallpaper Android itself rejected', () async {
      final FakeWallpaperApplier applier = FakeWallpaperApplier(
        failure: const WallpaperApplyFailure(WallpaperApplyProblem.rejected),
      );
      final ApplyDownload apply = ApplyDownload(applier: applier);

      await expectLater(
        apply(_download(), WallpaperTarget.lock),
        throwsA(
          isA<WallpaperApplyFailure>().having(
            (WallpaperApplyFailure failure) => failure.problem,
            'problem',
            WallpaperApplyProblem.rejected,
          ),
        ),
      );
      // A second attempt would fail the same way, at the price of a download.
      expect(applier.callCount, 1);
    });
  });
}

final Uri _location = Uri.parse(
  'content://media/external/images/media/42',
);

DownloadRecord _download() => DownloadRecord(
  wallpaper: const Wallpaper(
    id: 'e7jvjd',
    source: SourceId.wallhaven,
    fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
    resolution: Resolution(1440, 3200),
    fileSizeBytes: 2048,
    purity: Purity.sfw,
    category: Category.general,
    colors: <String>[],
  ),
  tier: StorageTier.sharedGallery,
  location: _location,
  downloadedAt: DateTime(2026, 7, 14),
);
