import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/offload_run.dart';
import 'package:tela/app/offload_run_controller.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/offload_group.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

import '../fakes/fake_app_visibility.dart';
import '../fakes/fake_download_history.dart';
import '../fakes/fake_download_queue.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_settings_repository.dart';

void main() {
  test('a started run reports itself before it finishes', () async {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);

    final bool started = harness.controller.start(<OffloadGroup>[_group(3)]);

    expect(started, isTrue);
    expect(harness.run?.phase, OffloadPhase.copying);
    expect(harness.run?.total, 3);
    await harness.settle();
  });

  test('it moves everything and reports the tally', () async {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);

    harness.controller.start(<OffloadGroup>[_group(3)]);
    await harness.settle();

    expect(harness.run?.isComplete, isTrue);
    expect(harness.run?.moved, 3);
    expect(harness.images.copies, hasLength(3));
  });

  /// The whole point of the controller living above the screens: a second
  /// start would copy what the first is still deleting.
  test('a second run is refused while one is in flight', () async {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);

    harness.controller.start(<OffloadGroup>[_group(3)]);
    final bool second = harness.controller.start(<OffloadGroup>[_group(3)]);

    expect(second, isFalse);
    await harness.settle();
  });

  test('an empty selection starts nothing', () {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);

    expect(harness.controller.start(<OffloadGroup>[_group(0)]), isFalse);
    expect(harness.run, isNull);
  });

  group('the delete waits for a screen', () {
    /// Only an Activity can raise the gallery's system delete confirmation, so
    /// a backgrounded delete cannot happen — and a move reads that as declined
    /// and undoes every copy behind it. Waiting is what makes a background
    /// offload safe rather than merely quiet.
    test('a backgrounded run copies but does not delete', () async {
      final _Harness harness = _Harness(foreground: false);
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[_group(2)]);
      await harness.settle();

      expect(harness.images.copies, hasLength(2), reason: 'copying is free');
      expect(harness.images.deletedLocations, isEmpty);
      expect(harness.run?.phase, OffloadPhase.waitingForScreen);
      expect(harness.visibility.waiting, 1);
    });

    test('coming back finishes the move', () async {
      final _Harness harness = _Harness(foreground: false);
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[_group(2)]);
      await harness.settle();
      harness.visibility.foreground();
      await harness.settle();

      expect(harness.run?.isComplete, isTrue);
      expect(harness.images.deletedLocations, hasLength(2));
    });

    test('a foreground run never waits at all', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[_group(2)]);
      await harness.settle();

      expect(harness.visibility.waiting, 0);
      expect(harness.run?.phase, OffloadPhase.done);
    });
  });

  group('stopping', () {
    /// Stop ends the copying, not the move: throwing away the files that had
    /// already made the trip is the opposite of what an impatient user means.
    test('what was already copied still completes its move', () async {
      final _Harness harness = _Harness(foreground: false);
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[_group(4)]);
      harness.controller.stop();
      await harness.settle();
      harness.visibility.foreground();
      await harness.settle();

      expect(harness.run?.isDone, isTrue);
      expect(harness.run?.stopping, isTrue);
      // Whatever the loop got through before noticing still moved; nothing was
      // undone, and nothing was left copied-but-not-deleted.
      expect(
        harness.images.deletedLocations.length,
        harness.images.copies.length,
      );
    });

    test('stopping marks the run so the button can go dead', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[_group(4)]);
      harness.controller.stop();

      expect(harness.run?.stopping, isTrue);
      await harness.settle();
    });

    test('stopping when nothing runs is a no-op', () {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.stop();

      expect(harness.run, isNull);
    });
  });

  group('re-routing after a move', () {
    test('safe downloads follow to the card', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[_group(1)]);
      await harness.settle();

      expect(harness.settings.saved.sfwTier, StorageTier.filesOutsideGallery);
      expect(harness.settings.saved.nsfwTier, StorageTier.appPrivate);
    });

    /// Leaving explicit downloads on the app-private tier would refill the disk
    /// that was just cleared with exactly what came off it.
    test('explicit downloads follow only when the vault moved', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[
        _group(1, kind: OffloadKind.privateLibrary),
      ]);
      await harness.settle();

      expect(harness.settings.saved.nsfwTier, StorageTier.filesOutsideGallery);
      expect(harness.queue.reroutes, <(StorageTier, StorageTier)>[
        (StorageTier.sharedGallery, StorageTier.filesOutsideGallery),
        (StorageTier.appPrivate, StorageTier.filesOutsideGallery),
      ]);
    });

    /// Queued batches carry their destination with them, so a gallery batch
    /// queued before the move would otherwise refill the gallery after it.
    test('queued gallery work follows to the card', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[_group(1)]);
      await harness.settle();

      expect(harness.queue.reroutes, <(StorageTier, StorageTier)>[
        (StorageTier.sharedGallery, StorageTier.filesOutsideGallery),
      ]);
    });

    group('a "Keep sending here" pin', () {
      /// Regression: the pin outranks the configured tier, so re-routing alone
      /// left a pinned user downloading straight back to built-in storage.
      test('on the gallery follows when the vault moved too', () async {
        final _Harness harness = _Harness(pin: StorageTier.sharedGallery);
        addTearDown(harness.dispose);

        harness.controller.start(<OffloadGroup>[
          _group(1),
          _group(1, kind: OffloadKind.privateLibrary),
        ]);
        await harness.settle();

        expect(
          harness.settings.pinnedTierSaved,
          StorageTier.filesOutsideGallery,
        );
      });

      /// Re-pinning to the card would send explicit downloads there too, which
      /// only ticking the private library may do.
      test('on the gallery is cleared when the vault stayed', () async {
        final _Harness harness = _Harness(pin: StorageTier.sharedGallery);
        addTearDown(harness.dispose);

        harness.controller.start(<OffloadGroup>[_group(1)]);
        await harness.settle();

        expect(harness.settings.pinnedTierSaved, isNull);
      });

      test('on the private library follows the vault', () async {
        final _Harness harness = _Harness(pin: StorageTier.appPrivate);
        addTearDown(harness.dispose);

        harness.controller.start(<OffloadGroup>[
          _group(1, kind: OffloadKind.privateLibrary),
        ]);
        await harness.settle();

        expect(
          harness.settings.pinnedTierSaved,
          StorageTier.filesOutsideGallery,
        );
      });

      test('on the private library stays when the vault stayed', () async {
        final _Harness harness = _Harness(pin: StorageTier.appPrivate);
        addTearDown(harness.dispose);

        harness.controller.start(<OffloadGroup>[_group(1)]);
        await harness.settle();

        expect(harness.settings.pinnedTierSaved, StorageTier.appPrivate);
      });
    });

    test('a run that moved nothing changes no setting', () async {
      final _Harness harness = _Harness(failEveryCopy: true);
      addTearDown(harness.dispose);

      harness.controller.start(<OffloadGroup>[_group(2)]);
      await harness.settle();

      expect(harness.settings.saved.sfwTier, StorageTier.sharedGallery);
    });
  });

  test('a finished run can be acknowledged away', () async {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);

    harness.controller.start(<OffloadGroup>[_group(1)]);
    await harness.settle();
    harness.controller.acknowledge();

    expect(harness.run, isNull);
  });

  test('a running one cannot be acknowledged away', () async {
    final _Harness harness = _Harness(foreground: false);
    addTearDown(harness.dispose);

    harness.controller.start(<OffloadGroup>[_group(1)]);
    await harness.settle();
    harness.controller.acknowledge();

    expect(harness.run, isNotNull);
    harness.visibility.foreground();
    await harness.settle();
  });
}

OffloadGroup _group(
  int count, {
  OffloadKind kind = OffloadKind.galleryDownloads,
}) {
  final bool private = kind == OffloadKind.privateLibrary;
  return OffloadGroup(
    kind: kind,
    bytes: count * 1024,
    moves: <StoredImageMove>[
      for (int i = 0; i < count; i++)
        StoredImageMove(
          ref: WallpaperRef(SourceId.wallhaven, 'id$i'),
          purity: private ? Purity.nsfw : Purity.sfw,
          from: private ? StorageTier.appPrivate : StorageTier.sharedGallery,
          location: Uri.parse('content://media/$i'),
          to: StorageTier.filesOutsideGallery,
        ),
    ],
  );
}

/// A container with every seam the runner touches, and a way to let it finish.
class _Harness {
  _Harness({
    bool foreground = true,
    bool failEveryCopy = false,
    StorageTier? pin,
  }) : settings = FakeSettingsRepository(pinnedDownloadTier: pin),
       visibility = FakeAppVisibility(foreground: foreground),
       images = FakeImageStore(
         failingIds: failEveryCopy
             ? <String>{for (int i = 0; i < 10; i++) 'id$i'}
             : const <String>{},
       ) {
    container = ProviderContainer(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(images),
        downloadHistoryProvider.overrideWithValue(FakeDownloadHistory()),
        downloadQueueProvider.overrideWithValue(queue),
        settingsRepositoryProvider.overrideWithValue(settings),
        appVisibilityProvider.overrideWithValue(visibility),
      ],
    );
  }

  final FakeAppVisibility visibility;
  final FakeImageStore images;
  final FakeSettingsRepository settings;
  final FakeDownloadQueue queue = FakeDownloadQueue();
  late final ProviderContainer container;

  OffloadRunController get controller =>
      container.read(offloadRunProvider.notifier);

  OffloadRun? get run => container.read(offloadRunProvider);

  /// Lets every pending future settle. The run is futures, not frames, so a
  /// handful of event-loop turns is all it takes.
  Future<void> settle() async {
    for (int i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void dispose() => container.dispose();
}
