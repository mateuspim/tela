import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/offload_group.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/domain/models/stored_image_size.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/survey_offload_groups.dart';

import '../../fakes/fake_download_history.dart';
import '../../fakes/fake_image_store.dart';

void main() {
  group('SurveyOffloadGroups', () {
    test(
      'splits recorded downloads into a gallery and a files group',
      () async {
        final DownloadRecord gallery = _record(
          'aaa',
          StorageTier.sharedGallery,
        );
        final DownloadRecord files = _record(
          'bbb',
          StorageTier.filesOutsideGallery,
        );
        final FakeImageStore images = FakeImageStore()
          ..sizes = <Uri, StoredImageSize>{
            gallery.location: _size(3000),
            files.location: _size(1000),
          };

        final List<OffloadGroup> groups = await _survey(
          images,
          FakeDownloadHistory(initial: <DownloadRecord>[gallery, files]),
        )();

        expect(
          groups.map((OffloadGroup g) => g.kind),
          <OffloadKind>[OffloadKind.galleryDownloads, OffloadKind.deviceFiles],
        );
        expect(groups.first.bytes, 3000);
        expect(groups.last.bytes, 1000);
      },
    );

    /// The whole promise of the screen is space returned to built-in storage,
    /// and a file already on the card returns none.
    test('leaves out rows whose file already sits on a card', () async {
      final DownloadRecord onCard = _record('aaa', StorageTier.sharedGallery);
      final DownloadRecord onDevice = _record('bbb', StorageTier.sharedGallery);
      final FakeImageStore images = FakeImageStore()
        ..sizes = <Uri, StoredImageSize>{
          onCard.location: const StoredImageSize(
            bytes: 9000,
            onRemovableVolume: true,
          ),
          onDevice.location: _size(1000),
        };

      final List<OffloadGroup> groups = await _survey(
        images,
        FakeDownloadHistory(
          initial: <DownloadRecord>[onCard, onDevice],
        ),
      )();

      expect(groups.single.count, 1);
      expect(groups.single.bytes, 1000);
      expect(groups.single.moves.single.ref.id, 'bbb');
    });

    /// A row measuring nothing is a file that could not be opened, which would
    /// also fail the copy — counting its bytes would overstate the tally.
    test('leaves out rows whose file could not be measured', () async {
      final DownloadRecord gone = _record('aaa', StorageTier.sharedGallery);

      final List<OffloadGroup> groups = await _survey(
        FakeImageStore(),
        FakeDownloadHistory(initial: <DownloadRecord>[gone]),
      )();

      expect(groups, isEmpty);
    });

    test('measures the whole history in one crossing', () async {
      final List<DownloadRecord> many = <DownloadRecord>[
        for (int i = 0; i < 20; i++) _record('id$i', StorageTier.sharedGallery),
      ];
      final FakeImageStore images = FakeImageStore()
        ..sizes = <Uri, StoredImageSize>{
          for (final DownloadRecord d in many) d.location: _size(10),
        };

      await _survey(images, FakeDownloadHistory(initial: many))();

      expect(images.measureAllCalls, 1);
    });

    test('every move points at the files tier and keeps its tag', () async {
      final DownloadRecord tagged = _record(
        'aaa',
        StorageTier.sharedGallery,
        tag: TagFolder('anime'),
      );
      final FakeImageStore images = FakeImageStore()
        ..sizes = <Uri, StoredImageSize>{tagged.location: _size(1000)};

      final List<OffloadGroup> groups = await _survey(
        images,
        FakeDownloadHistory(initial: <DownloadRecord>[tagged]),
      )();

      final StoredImageMove move = groups.single.moves.single;
      expect(move.to, StorageTier.filesOutsideGallery);
      expect(move.from, StorageTier.sharedGallery);
      expect(move.tag, TagFolder('anime'));
    });

    test(
      'the private library is its own group, sized from its listing',
      () async {
        final FakeImageStore images = FakeImageStore(
          privateLibrary: <PrivateImage>[
            _private('aaa', 500),
            _private('bbb', 700),
          ],
        );

        final List<OffloadGroup> groups = await _survey(
          images,
          FakeDownloadHistory(),
        )();

        expect(groups.single.kind, OffloadKind.privateLibrary);
        expect(groups.single.bytes, 1200);
        expect(
          images.measured,
          isEmpty,
          reason: 'the private listing already carries each size',
        );
      },
    );

    /// The tier keeps no record of what it holds, so nothing here may claim a
    /// private image is safe for the gallery — the adapter's own gate is what
    /// enforces it, and it can only do so if the caller declares `nsfw`.
    test(
      'private moves declare nsfw so the gallery stays impossible',
      () async {
        final FakeImageStore images = FakeImageStore(
          privateLibrary: <PrivateImage>[_private('aaa', 500)],
        );

        final List<OffloadGroup> groups = await _survey(
          images,
          FakeDownloadHistory(),
        )();

        expect(groups.single.moves.single.purity, Purity.nsfw);
      },
    );

    /// Vault images are already on the card, and offering them would be worse
    /// than a no-op: the copy resolves to the document it is reading.
    test('private images already in the vault are left out', () async {
      final FakeImageStore images = FakeImageStore(
        privateLibrary: <PrivateImage>[
          _private('aaa', 500),
          _private('bbb', 700, tier: StorageTier.filesOutsideGallery),
        ],
      );

      final List<OffloadGroup> groups = await _survey(
        images,
        FakeDownloadHistory(),
      )();

      expect(groups.single.count, 1);
      expect(groups.single.bytes, 500);
      expect(groups.single.moves.single.ref.id, 'aaa');
    });

    test('a library wholly in the vault offers no private group', () async {
      final FakeImageStore images = FakeImageStore(
        privateLibrary: <PrivateImage>[
          _private('aaa', 500, tier: StorageTier.filesOutsideGallery),
        ],
      );

      expect(await _survey(images, FakeDownloadHistory())(), isEmpty);
    });

    /// The cost, not the answer — both listings agree on which images belong
    /// in the group. Only one of them pays a crossing per file on the card to
    /// say so, and reaching for it made this screen slower every time it was
    /// used successfully.
    test('the survey never opens the vault', () async {
      final FakeImageStore images = FakeImageStore(
        privateLibrary: <PrivateImage>[
          _private('aaa', 500),
          _private('bbb', 700, tier: StorageTier.filesOutsideGallery),
        ],
      );

      await _survey(images, FakeDownloadHistory())();

      expect(images.vaultListings, 0);
    });

    test('an empty device answers no groups at all', () async {
      final List<OffloadGroup> groups = await _survey(
        FakeImageStore(),
        FakeDownloadHistory(),
      )();

      expect(groups, isEmpty);
    });
  });
}

SurveyOffloadGroups _survey(
  FakeImageStore images,
  FakeDownloadHistory history,
) => SurveyOffloadGroups(imageStore: images, history: history);

StoredImageSize _size(int bytes) =>
    StoredImageSize(bytes: bytes, onRemovableVolume: false);

DownloadRecord _record(String id, StorageTier tier, {TagFolder? tag}) =>
    DownloadRecord(
      wallpaper: _wallpaper(id),
      tier: tier,
      location: Uri.parse('content://media/external/images/media/$id'),
      downloadedAt: DateTime(2026, 8, 25),
      tag: tag,
    );

PrivateImage _private(
  String id,
  int bytes, {
  StorageTier tier = StorageTier.appPrivate,
}) => PrivateImage(
  ref: WallpaperRef(SourceId.wallhaven, id),
  location: Uri.parse('file:///data/tela/wallhaven-$id.jpg'),
  savedAt: DateTime(2026, 8, 25),
  sizeBytes: bytes,
  tier: tier,
);

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
