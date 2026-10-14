import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/broken_image.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image_condition.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/find_broken_images.dart';

import '../../fakes/fake_download_history.dart';
import '../../fakes/fake_image_store.dart';

/// Finding damaged files across every home tela has.
///
/// The case that prompted it: 0-byte leftovers of an unverified offload, in
/// the vault on the card — reachable only through the private library, since
/// explicit downloads write no history row (owner, 2026-10-07).
void main() {
  final Uri galleryUri = Uri.parse('content://media/g1');
  final Uri vaultUri = Uri.parse('content://tree/vault/p1');

  FindBrokenImages finder(FakeImageStore images, FakeDownloadHistory h) =>
      FindBrokenImages(imageStore: images, history: h);

  test('finds a broken file in the vault, tag and tier intact', () async {
    final FakeImageStore images =
        FakeImageStore(
            privateLibrary: <PrivateImage>[_private('p1', vaultUri)],
          )
          ..conditions = <Uri, StoredImageCondition>{
            vaultUri: StoredImageCondition.empty,
          };

    final List<BrokenImage> broken = await finder(
      images,
      FakeDownloadHistory(),
    )();

    expect(broken, <BrokenImage>[
      BrokenImage(
        ref: const WallpaperRef(SourceId.wallhaven, 'p1'),
        tier: StorageTier.filesOutsideGallery,
        tag: TagFolder('Byoru'),
        location: vaultUri,
        condition: StoredImageCondition.empty,
        recorded: false,
      ),
    ]);
  });

  test('a history row is marked as recorded', () async {
    final FakeImageStore images = FakeImageStore()
      ..conditions = <Uri, StoredImageCondition>{
        galleryUri: StoredImageCondition.truncated,
      };
    final FakeDownloadHistory history = FakeDownloadHistory(
      initial: <DownloadRecord>[_record('g1', galleryUri)],
    );

    final List<BrokenImage> broken = await finder(images, history)();

    expect(broken.single.recorded, isTrue);
    expect(broken.single.condition, StoredImageCondition.truncated);
  });

  /// A revoked grant or an ejected card is not damage: unreadable must never
  /// lead to an overwrite or a delete.
  test('intact and unreadable files are left out', () async {
    final FakeImageStore images =
        FakeImageStore(
            privateLibrary: <PrivateImage>[_private('p1', vaultUri)],
          )
          ..conditions = <Uri, StoredImageCondition>{
            vaultUri: StoredImageCondition.unreadable,
          };
    final FakeDownloadHistory history = FakeDownloadHistory(
      initial: <DownloadRecord>[_record('g1', galleryUri)],
    );

    expect(await finder(images, history)(), isEmpty);
  });

  test('a large library is inspected in chunks, reporting each', () async {
    final FakeImageStore images = FakeImageStore(
      privateLibrary: <PrivateImage>[
        for (int i = 0; i < 450; i++)
          _private('p$i', Uri.parse('content://tree/vault/p$i')),
      ],
    );
    final List<int> reported = <int>[];

    await finder(images, FakeDownloadHistory())(
      onProgress: (int done, int total) => reported.add(done),
    );

    expect(
      images.inspectedBatches.map((List<Uri> b) => b.length),
      <int>[200, 200, 50],
    );
    expect(reported, <int>[0, 200, 400, 450]);
  });
}

PrivateImage _private(String id, Uri location) => PrivateImage(
  ref: WallpaperRef(SourceId.wallhaven, id),
  location: location,
  savedAt: DateTime(2026, 10, 6),
  sizeBytes: 0,
  tier: StorageTier.filesOutsideGallery,
  tag: TagFolder('Byoru'),
);

DownloadRecord _record(String id, Uri location) => DownloadRecord(
  wallpaper: Wallpaper(
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
  ),
  tier: StorageTier.sharedGallery,
  location: location,
  downloadedAt: DateTime(2026, 10, 6),
);
