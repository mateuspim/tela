import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/configured_download.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/download_wallpaper.dart';

import '../fakes/fake_image_store.dart';

void main() {
  group('ConfiguredDownload', () {
    test('a configured tier stores at once, without asking a volume', () async {
      final _ScriptedDownload perform = _ScriptedDownload(<Object?>[null]);
      final FakeImageStore store = FakeImageStore();
      final _RecordingChooser chooser = _RecordingChooser(
        StorageVolumeKind.device,
      );
      final ConfiguredDownload download = ConfiguredDownload(
        perform: perform.call,
        imageStore: store,
      );

      final DownloadOutcome outcome = await download(
        _wallpaper('one'),
        chooseVolume: chooser.call,
      );

      expect(outcome, DownloadOutcome.saved);
      expect(perform.calls, 1);
      expect(chooser.calls, 0);
      expect(store.chosenKinds, isEmpty);
    });

    test(
      'an unconfigured folder runs the chooser, grants, and retries',
      () async {
        final _ScriptedDownload perform = _ScriptedDownload(<Object?>[
          const ImageStoreFailure(ImageStoreProblem.notConfigured),
          null,
        ]);
        final FakeImageStore store = FakeImageStore(chosenFolder: _folder());
        final _RecordingChooser chooser = _RecordingChooser(
          StorageVolumeKind.sdCard,
        );
        final ConfiguredDownload download = ConfiguredDownload(
          perform: perform.call,
          imageStore: store,
        );

        final DownloadOutcome outcome = await download(
          _wallpaper('two'),
          chooseVolume: chooser.call,
        );

        expect(outcome, DownloadOutcome.saved);
        expect(perform.calls, 2, reason: 'the download is retried after setup');
        expect(store.chosenKinds, <StorageVolumeKind>[
          StorageVolumeKind.sdCard,
        ]);
      },
    );

    test('the chooser is told whether a card is on offer', () async {
      final _ScriptedDownload perform = _ScriptedDownload(<Object?>[
        const ImageStoreFailure(ImageStoreProblem.notConfigured),
        null,
      ]);
      final FakeImageStore store = FakeImageStore(
        sdCardAvailable: true,
        chosenFolder: _folder(),
      );
      final _RecordingChooser chooser = _RecordingChooser(
        StorageVolumeKind.device,
      );
      final ConfiguredDownload download = ConfiguredDownload(
        perform: perform.call,
        imageStore: store,
      );

      await download(_wallpaper('three'), chooseVolume: chooser.call);

      expect(chooser.lastOfferSdCard, isTrue);
    });

    test('dismissing the chooser cancels, writing nothing', () async {
      final _ScriptedDownload perform = _ScriptedDownload(<Object?>[
        const ImageStoreFailure(ImageStoreProblem.notConfigured),
      ]);
      final FakeImageStore store = FakeImageStore(chosenFolder: _folder());
      final _RecordingChooser chooser = _RecordingChooser(null);
      final ConfiguredDownload download = ConfiguredDownload(
        perform: perform.call,
        imageStore: store,
      );

      final DownloadOutcome outcome = await download(
        _wallpaper('four'),
        chooseVolume: chooser.call,
      );

      expect(outcome, DownloadOutcome.cancelled);
      expect(perform.calls, 1, reason: 'no retry when the sheet was dismissed');
      expect(store.chosenKinds, isEmpty);
    });

    test('backing out of the system picker cancels too', () async {
      final _ScriptedDownload perform = _ScriptedDownload(<Object?>[
        const ImageStoreFailure(ImageStoreProblem.notConfigured),
      ]);
      final FakeImageStore store = FakeImageStore();
      final _RecordingChooser chooser = _RecordingChooser(
        StorageVolumeKind.device,
      );
      final ConfiguredDownload download = ConfiguredDownload(
        perform: perform.call,
        imageStore: store,
      );

      final DownloadOutcome outcome = await download(
        _wallpaper('five'),
        chooseVolume: chooser.call,
      );

      expect(outcome, DownloadOutcome.cancelled);
      expect(perform.calls, 1);
    });

    test('a grant that still will not store fails, it does not loop', () async {
      final _ScriptedDownload perform = _ScriptedDownload(<Object?>[
        const ImageStoreFailure(ImageStoreProblem.notConfigured),
        const ImageStoreFailure(ImageStoreProblem.notConfigured),
      ]);
      final FakeImageStore store = FakeImageStore(chosenFolder: _folder());
      final _RecordingChooser chooser = _RecordingChooser(
        StorageVolumeKind.device,
      );
      final ConfiguredDownload download = ConfiguredDownload(
        perform: perform.call,
        imageStore: store,
      );

      final DownloadOutcome outcome = await download(
        _wallpaper('six'),
        chooseVolume: chooser.call,
      );

      expect(outcome, DownloadOutcome.failed);
      expect(perform.calls, 2, reason: 'retried once, then gave up');
      expect(chooser.calls, 1);
    });

    test(
      'an unavailable folder reports itself, never asking or retrying',
      () async {
        // An ejected card is not first-time setup: offering the chooser would
        // ask a question the user already answered, and a silent reroute is the
        // trust failure the NSFW rules exist to prevent. It must surface as its
        // own outcome, distinct from a plain failure.
        final _ScriptedDownload perform = _ScriptedDownload(<Object?>[
          const ImageStoreFailure(ImageStoreProblem.folderUnavailable),
        ]);
        final FakeImageStore store = FakeImageStore(chosenFolder: _folder());
        final _RecordingChooser chooser = _RecordingChooser(
          StorageVolumeKind.device,
        );
        final ConfiguredDownload download = ConfiguredDownload(
          perform: perform.call,
          imageStore: store,
        );

        final DownloadOutcome outcome = await download(
          _wallpaper('unavailable'),
          chooseVolume: chooser.call,
        );

        expect(outcome, DownloadOutcome.folderUnavailable);
        expect(perform.calls, 1, reason: 'no retry for an ejected card');
        expect(chooser.calls, 0, reason: 'the folder exists; do not re-ask');
        expect(store.chosenKinds, isEmpty);
      },
    );

    test('any other failure fails without touching the chooser', () async {
      final _ScriptedDownload perform = _ScriptedDownload(<Object?>[
        const ImageStoreFailure(ImageStoreProblem.source),
      ]);
      final FakeImageStore store = FakeImageStore(chosenFolder: _folder());
      final _RecordingChooser chooser = _RecordingChooser(
        StorageVolumeKind.device,
      );
      final ConfiguredDownload download = ConfiguredDownload(
        perform: perform.call,
        imageStore: store,
      );

      final DownloadOutcome outcome = await download(
        _wallpaper('seven'),
        chooseVolume: chooser.call,
      );

      expect(outcome, DownloadOutcome.failed);
      expect(chooser.calls, 0);
      expect(store.chosenKinds, isEmpty);
    });

    // Safe and explicit downloads each have their own folder (owner,
    // 2026-10-16), so first-time setup must grant the one this wallpaper needs.
    test('an explicit wallpaper sets up the explicit folder', () async {
      final _ScriptedDownload perform = _ScriptedDownload(<Object?>[
        const ImageStoreFailure(ImageStoreProblem.notConfigured),
        null,
      ]);
      final FakeImageStore store = FakeImageStore(chosenFolder: _folder());
      final ConfiguredDownload download = ConfiguredDownload(
        perform: perform.call,
        imageStore: store,
      );

      await download(
        _wallpaper('three', purity: Purity.nsfw),
        chooseVolume: _RecordingChooser(StorageVolumeKind.sdCard).call,
      );

      expect(store.chosenPurities, <Purity>[Purity.nsfw]);
    });
  });

  group('ensureFolder', () {
    test('asks nothing when the needed folder is already granted', () async {
      final FakeImageStore store = FakeImageStore(folder: _folder());
      final _RecordingChooser chooser = _RecordingChooser(
        StorageVolumeKind.device,
      );

      final bool ready = await ConfiguredDownload(
        perform: _ScriptedDownload(<Object?>[]).call,
        imageStore: store,
      ).ensureFolder(chooser.call, purities: <Purity>{Purity.sketchy});

      expect(ready, isTrue);
      expect(chooser.calls, 0);
    });

    test('grants only the explicit folder for an explicit batch', () async {
      final FakeImageStore store = FakeImageStore(chosenFolder: _folder());

      final bool ready =
          await ConfiguredDownload(
            perform: _ScriptedDownload(<Object?>[]).call,
            imageStore: store,
          ).ensureFolder(
            _RecordingChooser(StorageVolumeKind.sdCard).call,
            purities: <Purity>{Purity.nsfw},
          );

      expect(ready, isTrue);
      expect(store.chosenPurities, <Purity>[Purity.nsfw]);
    });

    test('a mixed batch grants the safe folder first', () async {
      // A first safe folder is where explicit downloads go too until one is
      // chosen apart, so one grant settles both buckets.
      final FakeImageStore store = FakeImageStore(chosenFolder: _folder());

      await ConfiguredDownload(
        perform: _ScriptedDownload(<Object?>[]).call,
        imageStore: store,
      ).ensureFolder(
        _RecordingChooser(StorageVolumeKind.sdCard).call,
        purities: <Purity>{Purity.nsfw, Purity.sfw},
      );

      expect(store.chosenPurities, <Purity>[Purity.sfw]);
    });

    test('backing out answers false', () async {
      final bool ready =
          await ConfiguredDownload(
            perform: _ScriptedDownload(<Object?>[]).call,
            imageStore: FakeImageStore(),
          ).ensureFolder(
            _RecordingChooser(null).call,
            purities: <Purity>{Purity.sfw},
          );

      expect(ready, isFalse);
    });
  });
}

/// A [PerformDownload] scripted with one response per call: null succeeds, an
/// [ImageStoreFailure] is thrown.
class _ScriptedDownload {
  _ScriptedDownload(this._responses);

  final List<Object?> _responses;
  int calls = 0;

  Future<void> call(
    Wallpaper wallpaper, {
    StorageTier? tier,
    TagFolder? tag,
  }) async {
    final Object? response = _responses[calls];
    calls++;
    if (response is ImageStoreFailure) throw response;
  }
}

/// A [ChooseDownloadVolume] that answers a fixed pick and records its offer.
class _RecordingChooser {
  _RecordingChooser(this._pick);

  final StorageVolumeKind? _pick;
  int calls = 0;
  bool? lastOfferSdCard;

  Future<StorageVolumeKind?> call({required bool offerSdCard}) async {
    calls++;
    lastOfferSdCard = offerSdCard;
    return _pick;
  }
}

DownloadFolder _folder() => const DownloadFolder(
  volumeLabel: 'SD card',
  relativePath: 'Wallpapers/tela',
  isRemovable: true,
  isAvailable: true,
);

Wallpaper _wallpaper(String id, {Purity purity = Purity.sfw}) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
