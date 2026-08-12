import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/move_stored_images.dart';
import 'package:tela/domain/use_cases/retag_stored_images.dart';

import '../../fakes/fake_download_history.dart';
import '../../fakes/fake_image_store.dart';

/// Refiling downloads that are already on the device.
///
/// The behaviour worth defending is the **fast path and its fallback**. A tag
/// is a directory, so changing one should be a rename — no bytes, and no system
/// delete prompt, which every gallery delete raises on Android 30+. But media
/// ownership is per install, so a file written before the 2026-08-11 reinstall
/// cannot be moved in place, and those have to fall back to copy-and-delete
/// without the caller noticing.
void main() {
  late FakeImageStore images;
  late FakeDownloadHistory history;
  late RetagStoredImages retag;

  DownloadRecord recorded(String id, {TagFolder? tag}) => DownloadRecord(
    wallpaper: _wallpaper(id),
    tier: StorageTier.sharedGallery,
    location: Uri.parse('content://media/$id'),
    downloadedAt: DateTime(2026, 8, 12),
    tag: tag,
  );

  StoredImageRetag asking(DownloadRecord record, TagFolder? to) =>
      StoredImageRetag(
        ref: record.wallpaper.ref,
        purity: record.wallpaper.purity,
        tier: record.tier,
        location: record.location,
        to: to,
      );

  setUp(() {
    images = FakeImageStore();
    history = FakeDownloadHistory();
    retag = RetagStoredImages(
      imageStore: images,
      history: history,
      moveStoredImages: MoveStoredImages(imageStore: images, history: history),
    );
  });

  /// No bytes copied and no delete attempted — which is what keeps a selection
  /// of thirty from raising thirty system prompts.
  test('moves in place without copying or deleting', () async {
    final DownloadRecord record = recorded('a');
    await history.record(
      wallpaper: record.wallpaper,
      tier: record.tier,
      location: record.location,
    );

    final Set<WallpaperRef> moved = await retag(<StoredImageRetag>[
      asking(record, TagFolder('anime')),
    ]);

    expect(moved, <WallpaperRef>{record.wallpaper.ref});
    expect(images.retags, hasLength(1));
    expect(images.copies, isEmpty);
    expect(images.deletedRefs, isEmpty);
  });

  /// Both halves together: a row naming the new tag beside the old path
  /// describes a file that is not there.
  test('re-points the history row at the new location and tag', () async {
    final DownloadRecord record = recorded('a');
    await history.record(
      wallpaper: record.wallpaper,
      tier: record.tier,
      location: record.location,
    );

    await retag(<StoredImageRetag>[asking(record, TagFolder('anime'))]);

    final DownloadRecord after = history.recorded.single;
    expect(after.tag, TagFolder('anime'));
    expect(after.location, isNot(record.location));
  });

  test('a null tag moves it back to the tier root', () async {
    final DownloadRecord record = recorded('a', tag: TagFolder('anime'));
    await history.record(
      wallpaper: record.wallpaper,
      tier: record.tier,
      location: record.location,
      tag: TagFolder('anime'),
    );

    await retag(<StoredImageRetag>[asking(record, null)]);

    expect(history.recorded.single.tag, isNull);
  });

  group('when the file cannot be moved in place', () {
    /// Media ownership does not survive a reinstall, so this is the ordinary
    /// state of every file older than the last one — not an edge case.
    test('falls back to copying and deleting', () async {
      final DownloadRecord record = recorded('a');
      images.unretaggable = <Uri>{record.location};
      await history.record(
        wallpaper: record.wallpaper,
        tier: record.tier,
        location: record.location,
      );

      final Set<WallpaperRef> moved = await retag(<StoredImageRetag>[
        asking(record, TagFolder('anime')),
      ]);

      expect(moved, <WallpaperRef>{record.wallpaper.ref});
      expect(images.copies.single.tag, TagFolder('anime'));
    });

    /// **The one that would be silently wrong.** `MoveStoredImages` forgets the
    /// row on a successful move, which is right for a move into the private
    /// library and disastrous here: the download is still an ordinary one,
    /// sitting in the gallery, and forgetting it would erase its history for a
    /// file that never left.
    test('keeps the history row instead of forgetting it', () async {
      final DownloadRecord record = recorded('a');
      images.unretaggable = <Uri>{record.location};
      await history.record(
        wallpaper: record.wallpaper,
        tier: record.tier,
        location: record.location,
      );

      await retag(<StoredImageRetag>[asking(record, TagFolder('anime'))]);

      expect(history.recorded, hasLength(1));
      expect(history.recorded.single.tag, TagFolder('anime'));
    });

    /// A declined system prompt leaves the original where it was, so nothing
    /// moved — and the caller has to be told that rather than the count it
    /// asked for.
    test('reports nothing moved when the delete is declined', () async {
      final DownloadRecord record = recorded('a');
      final FakeImageStore declining = FakeImageStore(
        declined: <Uri>{record.location},
      )..unretaggable = <Uri>{record.location};
      final RetagStoredImages refusing = RetagStoredImages(
        imageStore: declining,
        history: history,
        moveStoredImages: MoveStoredImages(
          imageStore: declining,
          history: history,
        ),
      );

      final Set<WallpaperRef> moved = await refusing(<StoredImageRetag>[
        asking(record, TagFolder('anime')),
      ]);

      expect(moved, isEmpty);
    });
  });

  /// One stubborn file in a selection of three is a reason to report "moved 2
  /// of 3", not to abandon the other two.
  test('mixes the fast path and the fallback in one call', () async {
    final DownloadRecord fast = recorded('a');
    final DownloadRecord slow = recorded('b');
    images.unretaggable = <Uri>{slow.location};

    final Set<WallpaperRef> moved = await retag(<StoredImageRetag>[
      asking(fast, TagFolder('anime')),
      asking(slow, TagFolder('anime')),
    ]);

    expect(moved, hasLength(2));
    expect(images.retags, hasLength(1));
    expect(images.copies, hasLength(1));
  });

  test('an empty list touches nothing', () async {
    expect(await retag(const <StoredImageRetag>[]), isEmpty);
    expect(images.retags, isEmpty);
  });
}

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
