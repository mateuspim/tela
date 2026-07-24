import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/delete_downloads.dart';

import '../../fakes/fake_download_history.dart';
import '../../fakes/fake_image_store.dart';

void main() {
  group('DeleteDownloads', () {
    test('deletes every file and forgets every row', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record('e7jvjd'), _record('9dm5kg')],
      );
      final DeleteDownloads delete = DeleteDownloads(
        imageStore: imageStore,
        history: history,
      );

      final int gone = await delete(await history.downloads());

      expect(gone, 2);
      expect(imageStore.deletedLocations, hasLength(2));
      expect(history.recorded, isEmpty);
    });

    test('hands the whole selection over in one call', () async {
      // The point of the bulk path: one native round trip, so the gallery tier
      // resolves to a single system prompt rather than one per file.
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record('e7jvjd'), _record('9dm5kg')],
      );
      final DeleteDownloads delete = DeleteDownloads(
        imageStore: imageStore,
        history: history,
      );

      await delete(await history.downloads());

      expect(imageStore.batchSizes, <int>[2]);
    });

    test('forgets only the rows whose files actually went', () async {
      final FakeImageStore imageStore = FakeImageStore(
        declined: <Uri>{_locationOf('9dm5kg')},
      );
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record('e7jvjd'), _record('9dm5kg')],
      );
      final DeleteDownloads delete = DeleteDownloads(
        imageStore: imageStore,
        history: history,
      );

      final int gone = await delete(await history.downloads());

      // A declined prompt leaves that file *and* its row exactly as they were —
      // the row is the only pointer the user has left to it.
      expect(gone, 1);
      expect(
        history.recorded.map((DownloadRecord r) => r.wallpaper.id),
        <String>['9dm5kg'],
      );
    });

    test('an empty selection never reaches the store', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final DeleteDownloads delete = DeleteDownloads(
        imageStore: imageStore,
        history: FakeDownloadHistory(),
      );

      expect(await delete(const <DownloadRecord>[]), 0);
      expect(imageStore.batchSizes, isEmpty);
    });
  });
}

Uri _locationOf(String id) =>
    Uri.parse('content://media/external/images/media/$id');

DownloadRecord _record(String id) => DownloadRecord(
  wallpaper: _wallpaper(id),
  tier: StorageTier.sharedGallery,
  location: _locationOf(id),
  downloadedAt: DateTime.utc(2026, 7, 14),
);

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/$id.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
