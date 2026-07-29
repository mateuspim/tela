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

    // A selection of hundreds crossed once and answered only when the last
    // file had settled, so there was no number to show and the screen looked
    // frozen (owner, 2026-07-28).
    test('a large selection of files reports progress as it goes', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[
          for (int i = 0; i < 45; i++) _fileRecord('id$i'),
        ],
      );
      final DeleteDownloads delete = DeleteDownloads(
        imageStore: imageStore,
        history: history,
      );

      final List<int> reported = <int>[];
      final int gone = await delete(
        await history.downloads(),
        onProgress: (int done, int total) {
          expect(total, 45);
          reported.add(done);
        },
      );

      expect(gone, 45);
      // Chunks of 20, then the final call that closes the count out.
      expect(reported, <int>[20, 40, 45, 45]);
      expect(imageStore.batchSizes, <int>[20, 20, 5]);
    });

    /// The gallery tier's deletes need the OS's own confirmation, and the
    /// platform folds whatever it is handed into **one** prompt. Splitting them
    /// across chunks would ask the user to confirm the same delete over and
    /// over, once per chunk — so they go last, whole, however many there are.
    test('the gallery tier still crosses in exactly one call', () async {
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[
          for (int i = 0; i < 30; i++) _record('gallery$i'),
        ],
      );
      final DeleteDownloads delete = DeleteDownloads(
        imageStore: imageStore,
        history: history,
      );

      await delete(await history.downloads());

      expect(imageStore.batchSizes, <int>[30]);
    });

    test(
      'a mixed selection chunks the files and keeps one gallery call',
      () async {
        final FakeImageStore imageStore = FakeImageStore();
        final FakeDownloadHistory history = FakeDownloadHistory(
          initial: <DownloadRecord>[
            for (int i = 0; i < 25; i++) _fileRecord('file$i'),
            for (int i = 0; i < 25; i++) _record('gallery$i'),
          ],
        );
        final DeleteDownloads delete = DeleteDownloads(
          imageStore: imageStore,
          history: history,
        );

        await delete(await history.downloads());

        // 20 + 5 files, then the 25 gallery rows together — never interleaved,
        // or the prompt would land in the middle of the silent work.
        expect(imageStore.batchSizes, <int>[20, 5, 25]);
      },
    );

    test(
      'progress ends at the whole selection even when nothing went',
      () async {
        final FakeImageStore imageStore = FakeImageStore(
          declined: <Uri>{_locationOf('e7jvjd'), _locationOf('9dm5kg')},
        );
        final FakeDownloadHistory history = FakeDownloadHistory(
          initial: <DownloadRecord>[_record('e7jvjd'), _record('9dm5kg')],
        );
        final DeleteDownloads delete = DeleteDownloads(
          imageStore: imageStore,
          history: history,
        );

        final List<int> reported = <int>[];
        final int gone = await delete(
          await history.downloads(),
          onProgress: (int done, int _) => reported.add(done),
        );

        // A declined prompt deletes nothing, but the batch is still over — a
        // progress bar stuck below full would leave the dialog looking hung.
        expect(gone, 0);
        expect(reported.last, 2);
      },
    );
  });
}

/// A download in the files-outside-gallery tier, which needs no system prompt
/// and is therefore the tier that gets chunked.
DownloadRecord _fileRecord(String id) => DownloadRecord(
  wallpaper: _wallpaper(id),
  tier: StorageTier.filesOutsideGallery,
  location: _locationOf(id),
  downloadedAt: DateTime.utc(2026, 7, 14),
);

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
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
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
