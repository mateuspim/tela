import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_deletion.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/delete_download.dart';

import '../../fakes/fake_download_history.dart';
import '../../fakes/fake_image_store.dart';

void main() {
  group('DeleteDownload', () {
    test('deletes the file, then forgets its history row', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record()],
      );
      final DeleteDownload delete = DeleteDownload(
        imageStore: imageStore,
        history: history,
      );

      final DownloadDeletion outcome = await delete(
        ref: _ref,
        tier: StorageTier.sharedGallery,
        location: _location,
      );

      expect(outcome, DownloadDeletion.deleted);
      expect(imageStore.deletedLocations, <Uri>[_location]);
      expect(imageStore.deletedTiers, <StorageTier>[StorageTier.sharedGallery]);
      expect(history.recorded, isEmpty);
    });

    test('leaves the row alone when the user declines the prompt', () async {
      final FakeImageStore imageStore = FakeImageStore(
        declined: <Uri>{_location},
      );
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record()],
      );
      final DeleteDownload delete = DeleteDownload(
        imageStore: imageStore,
        history: history,
      );

      final DownloadDeletion outcome = await delete(
        ref: _ref,
        tier: StorageTier.sharedGallery,
        location: _location,
      );

      // A decline is not a deletion: nothing removed, the row still there.
      expect(outcome, DownloadDeletion.declined);
      expect(imageStore.deletedLocations, isEmpty);
      expect(history.recorded, hasLength(1));
    });

    test('rethrows a real failure and keeps the row', () async {
      final FakeImageStore imageStore = FakeImageStore(
        failure: const ImageStoreFailure(ImageStoreProblem.unavailable),
      );
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record()],
      );
      final DeleteDownload delete = DeleteDownload(
        imageStore: imageStore,
        history: history,
      );

      await expectLater(
        delete(
          ref: _ref,
          tier: StorageTier.filesOutsideGallery,
          location: _location,
        ),
        throwsA(isA<ImageStoreFailure>()),
      );
      // A failed file delete must not orphan the row's disappearance.
      expect(history.recorded, hasLength(1));
    });

    test('forgets the row when the file was already gone', () async {
      // The delete fails, but the file cannot be read anyway — the missing
      // badge case — so the row is a dead pointer and forgetting it is the
      // end state we wanted, not an error to surface.
      final FakeImageStore imageStore = FakeImageStore(
        failure: const ImageStoreFailure(ImageStoreProblem.unavailable),
        unreadable: <Uri>{_location},
      );
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record()],
      );
      final DeleteDownload delete = DeleteDownload(
        imageStore: imageStore,
        history: history,
      );

      final DownloadDeletion outcome = await delete(
        ref: _ref,
        tier: StorageTier.filesOutsideGallery,
        location: _location,
      );

      expect(outcome, DownloadDeletion.deleted);
      expect(history.recorded, isEmpty);
    });

    test('an app-private delete has no row to forget', () async {
      // Nothing app-private is ever recorded, so the history has no row; the
      // private library still shares this one delete path.
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory();
      final DeleteDownload delete = DeleteDownload(
        imageStore: imageStore,
        history: history,
      );

      final DownloadDeletion outcome = await delete(
        ref: _ref,
        tier: StorageTier.appPrivate,
        location: _location,
      );

      expect(outcome, DownloadDeletion.deleted);
      expect(imageStore.deletedTiers, <StorageTier>[StorageTier.appPrivate]);
    });
  });
}

final Uri _location = Uri.parse('content://media/external/images/media/42');

DownloadRecord _record() => DownloadRecord(
  wallpaper: _wallpaper,
  tier: StorageTier.sharedGallery,
  location: _location,
  downloadedAt: DateTime.utc(2026, 7, 14),
);

Wallpaper _wallpaper = Wallpaper(
  id: 'e7jvjd',
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);

/// The one wallpaper every case here deletes.
const WallpaperRef _ref = WallpaperRef(SourceId.wallhaven, 'e7jvjd');
