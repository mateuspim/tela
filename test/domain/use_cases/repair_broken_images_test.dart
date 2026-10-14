import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/broken_image.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/repair_tally.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/stored_image_condition.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/repair_broken_images.dart';

import '../../fakes/fake_download_history.dart';
import '../../fakes/fake_image_store.dart';

/// Putting a good copy back, or removing what cannot be had again.
void main() {
  late _FakeWallpaperLookup lookup;
  late _FakeWallpaperStoring storing;
  late FakeImageStore images;
  late FakeDownloadHistory history;

  RepairBrokenImages repair() => RepairBrokenImages(
    fetch: lookup.fetch,
    store: storing.store,
    imageStore: images,
    history: history,
  );

  setUp(() {
    lookup = _FakeWallpaperLookup();
    storing = _FakeWallpaperStoring();
    images = FakeImageStore();
    history = FakeDownloadHistory();
  });

  test('re-downloads into the same tier and tag folder', () async {
    final RepairTally tally = await repair()(<BrokenImage>[_broken('a')]);

    expect(tally, const RepairTally(repaired: 1, removed: 0, failed: 0));
    expect(storing.stored.single.tier, StorageTier.filesOutsideGallery);
    expect(storing.stored.single.tag, TagFolder('Byoru'));
    expect(images.deletedLocations, isEmpty, reason: 'overwritten in place');
  });

  /// The owner's choice was "delete, then re-download": no broken file may
  /// outlive a repair just because the source no longer has it.
  test('deletes what the source no longer has', () async {
    lookup.missing.add('a');

    final RepairTally tally = await repair()(<BrokenImage>[_broken('a')]);

    expect(tally, const RepairTally(repaired: 0, removed: 1, failed: 0));
    expect(images.deletedLocations, <Uri>[_uri('a')]);
  });

  test('deletes what could not be stored', () async {
    storing.failing.add('a');

    final RepairTally tally = await repair()(<BrokenImage>[_broken('a')]);

    expect(tally.removed, 1);
  });

  test('a declined delete is counted as still broken', () async {
    lookup.missing.add('a');
    images = FakeImageStore(declined: <Uri>{_uri('a')});

    final RepairTally tally = await repair()(<BrokenImage>[_broken('a')]);

    expect(tally, const RepairTally(repaired: 0, removed: 0, failed: 1));
  });

  /// A private image's ref can also name a different, healthy download with a
  /// row of its own; forgetting by ref would drop that one too.
  test('forgets only the rows that pointed at a deleted file', () async {
    lookup.missing.addAll(<String>['row', 'vault']);
    history = FakeDownloadHistory(initial: <DownloadRecord>[_row('row')]);

    await repair()(<BrokenImage>[
      _broken('row', recorded: true),
      _broken('vault'),
    ]);

    expect(history.recorded, isEmpty);
    expect(history.forgetAllBatchSizes, <int>[1]);
  });

  /// The total goes out before the first image: without it the dialog read
  /// "Repairing 0 of 0" for as long as the first download took (owner, on
  /// device, 2026-10-13).
  test('reports the total up front, then each image as it settles', () async {
    final List<(int, int)> reported = <(int, int)>[];

    await repair()(
      <BrokenImage>[_broken('a'), _broken('b')],
      onProgress: (int done, int total) => reported.add((done, total)),
    );

    expect(reported, <(int, int)>[(0, 2), (1, 2), (2, 2)]);
  });
}

/// Stands in for a source lookup by id; ids in [missing] are gone.
class _FakeWallpaperLookup {
  final Set<String> missing = <String>{};

  Future<Wallpaper> fetch(WallpaperRef ref) async {
    if (missing.contains(ref.id)) throw NotFoundFailure(ref.id);
    return _wallpaper(ref.id);
  }
}

/// Stands in for `DownloadWallpaper`; ids in [failing] fail to store.
class _FakeWallpaperStoring {
  final Set<String> failing = <String>{};
  final List<StoredImage> stored = <StoredImage>[];

  Future<StoredImage> store(
    Wallpaper wallpaper, {
    required StorageTier tier,
    TagFolder? tag,
  }) async {
    if (failing.contains(wallpaper.id)) {
      throw const ImageStoreFailure(ImageStoreProblem.unavailable);
    }
    final StoredImage image = StoredImage(
      location: _uri(wallpaper.id),
      tier: tier,
      tag: tag,
    );
    stored.add(image);
    return image;
  }
}

Uri _uri(String id) => Uri.parse('content://tree/vault/$id');

BrokenImage _broken(String id, {bool recorded = false}) => BrokenImage(
  ref: WallpaperRef(SourceId.wallhaven, id),
  tier: StorageTier.filesOutsideGallery,
  tag: TagFolder('Byoru'),
  location: _uri(id),
  condition: StoredImageCondition.empty,
  recorded: recorded,
);

DownloadRecord _row(String id) => DownloadRecord(
  wallpaper: _wallpaper(id),
  tier: StorageTier.filesOutsideGallery,
  location: _uri(id),
  downloadedAt: DateTime(2026, 10, 6),
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
