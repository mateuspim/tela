import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/move_stored_images.dart';

import '../../fakes/fake_download_history.dart';
import '../../fakes/fake_image_store.dart';

void main() {
  group('MoveStoredImages', () {
    test('copies the file locally, then deletes the original', () async {
      final FakeImageStore images = FakeImageStore();
      final MoveStoredImages move = _move(images);

      final Set<WallpaperRef> moved = await move(<StoredImageMove>[
        _toPrivate('e7jvjd'),
      ]);

      expect(moved, <WallpaperRef>{_ref('e7jvjd')});
      expect(images.copies.single.tier, StorageTier.appPrivate);
      expect(images.copies.single.from, _locationOf('e7jvjd'));
      expect(images.deletedLocations, <Uri>[_locationOf('e7jvjd')]);
      // Never re-fetched: the bytes were already on the device.
      expect(images.receivedImageUrl, isNull);
    });

    test('deletes the originals in one call, not one per file', () async {
      // The whole reason `deleteDownloads` exists: on Android 30+ each gallery
      // delete raises its own system prompt, and thirty prompts for one "move
      // these to the private library" is a punishment, not a feature.
      final FakeImageStore images = FakeImageStore();
      final MoveStoredImages move = _move(images);

      await move(<StoredImageMove>[
        _toPrivate('a'),
        _toPrivate('b'),
        _toPrivate('c'),
      ]);

      expect(images.batchSizes, <int>[3]);
    });

    test('forgets the history row of everything that moved', () async {
      // A private download is never recorded, so a row that outlived its file's
      // move would be an ungated index of exactly what went private.
      final FakeImageStore images = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record('e7jvjd')],
      );
      final MoveStoredImages move = _move(images, history: history);

      await move(<StoredImageMove>[_toPrivate('e7jvjd')]);

      expect(await history.downloads(), isEmpty);
    });

    test('a declined delete undoes the copy and moves nothing', () async {
      // The load-bearing case. Dismissing the system prompt leaves the original
      // in place, and a copy beside it would put the wallpaper in *two* tiers —
      // one of them the private library, while it is still in Photos.
      final FakeImageStore images = FakeImageStore(
        declined: <Uri>{_locationOf('e7jvjd')},
      );
      final MoveStoredImages move = _move(images);

      final Set<WallpaperRef> moved = await move(<StoredImageMove>[
        _toPrivate('e7jvjd'),
      ]);

      expect(moved, isEmpty);
      // The copy was made and then taken back off the device.
      expect(images.copies, hasLength(1));
      expect(
        images.deletedLocations,
        contains(Uri.parse('memory://e7jvjd-copy')),
      );
    });

    test('a declined delete leaves the history row alone', () async {
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_record('e7jvjd')],
      );
      final MoveStoredImages move = _move(
        FakeImageStore(declined: <Uri>{_locationOf('e7jvjd')}),
        history: history,
      );

      await move(<StoredImageMove>[_toPrivate('e7jvjd')]);

      expect(await history.downloads(), hasLength(1));
    });

    test('one declined delete does not hold up the rest', () async {
      final FakeImageStore images = FakeImageStore(
        declined: <Uri>{_locationOf('a')},
      );
      final MoveStoredImages move = _move(images);

      final Set<WallpaperRef> moved = await move(<StoredImageMove>[
        _toPrivate('a'),
        _toPrivate('b'),
      ]);

      expect(moved, <WallpaperRef>{_ref('b')});
    });

    test('a copy that fails takes that move and no other', () async {
      final FakeImageStore images = FakeImageStore(
        failingIds: const <String>{'a'},
      );
      final MoveStoredImages move = _move(images);

      final Set<WallpaperRef> moved = await move(<StoredImageMove>[
        _toPrivate('a'),
        _toPrivate('b'),
      ]);

      expect(moved, <WallpaperRef>{_ref('b')});
      // The failed one's original was never even offered for deletion.
      expect(images.deletedLocations, <Uri>[_locationOf('b')]);
    });

    test(
      'moving out declares nsfw, so the gallery is refused outright',
      () async {
        // Not a claim the image is explicit — a refusal to claim it is not. The
        // private tier keeps no record of what it holds beyond a file name, and
        // the storage adapter's own gate is what makes Photos impossible.
        final FakeImageStore images = FakeImageStore();
        final MoveStoredImages move = _move(images);

        final Set<WallpaperRef> moved = await move(<StoredImageMove>[
          StoredImageMove(
            ref: _ref('e7jvjd'),
            purity: Purity.nsfw,
            from: StorageTier.appPrivate,
            location: _locationOf('e7jvjd'),
            to: StorageTier.sharedGallery,
          ),
        ]);

        expect(moved, isEmpty);
        expect(images.copies, isEmpty);
      },
    );

    test(
      'moving out to the files tier works, and needs no history row',
      () async {
        final FakeImageStore images = FakeImageStore();
        final MoveStoredImages move = _move(images);

        final Set<WallpaperRef> moved = await move(<StoredImageMove>[
          StoredImageMove(
            ref: _ref('e7jvjd'),
            purity: Purity.nsfw,
            from: StorageTier.appPrivate,
            location: _locationOf('e7jvjd'),
            to: StorageTier.filesOutsideGallery,
          ),
        ]);

        expect(moved, <WallpaperRef>{_ref('e7jvjd')});
        expect(images.copies.single.tier, StorageTier.filesOutsideGallery);
      },
    );

    test('an empty list touches nothing', () async {
      final FakeImageStore images = FakeImageStore();

      expect(await _move(images)(<StoredImageMove>[]), isEmpty);
      expect(images.batchSizes, isEmpty);
    });

    test('nothing is deleted when every copy failed', () async {
      // A delete call with no successful copies behind it would ask the user to
      // confirm removing files that have nowhere to go.
      final FakeImageStore images = FakeImageStore(
        failure: const ImageStoreFailure(ImageStoreProblem.unavailable),
      );
      final MoveStoredImages move = _move(images);

      expect(await move(<StoredImageMove>[_toPrivate('a')]), isEmpty);
      expect(images.batchSizes, isEmpty);
    });
  });
}

MoveStoredImages _move(FakeImageStore images, {FakeDownloadHistory? history}) =>
    MoveStoredImages(
      imageStore: images,
      history: history ?? FakeDownloadHistory(),
    );

StoredImageMove _toPrivate(String id) => StoredImageMove(
  ref: _ref(id),
  purity: Purity.sfw,
  from: StorageTier.sharedGallery,
  location: _locationOf(id),
  to: StorageTier.appPrivate,
);

WallpaperRef _ref(String id) => WallpaperRef(SourceId.wallhaven, id);

Uri _locationOf(String id) => Uri.parse('content://media/$id');

DownloadRecord _record(String id) => DownloadRecord(
  wallpaper: _wallpaper(id),
  tier: StorageTier.sharedGallery,
  location: _locationOf(id),
  downloadedAt: DateTime.utc(2026, 7, 27),
);

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/xx/wallhaven-$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/xx/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/xx/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/xx/$id.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
