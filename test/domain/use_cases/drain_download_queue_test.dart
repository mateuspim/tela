import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/drain_download_queue.dart';

import '../../fakes/fake_download_queue.dart';

void main() {
  group('DrainDownloadQueue', () {
    test('empties the queue, taking every entry out as it lands', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b', 'c']);
      final List<String> downloaded = <String>[];

      await _drain(queue, onDownload: (Wallpaper w) => downloaded.add(w.id));

      expect(downloaded, <String>['a', 'b', 'c']);
      expect(await queue.entries(), isEmpty);
    });

    test('forwards the entry’s own tier override, per entry', () async {
      final FakeDownloadQueue queue = FakeDownloadQueue(
        initial: <QueuedDownload>[
          _entry('a', tier: StorageTier.appPrivate),
          _entry('b'),
        ],
      );
      final Map<String, StorageTier?> tiers = <String, StorageTier?>{};

      await _drain(
        queue,
        onDownloadWithTier: (Wallpaper w, StorageTier? tier) =>
            tiers[w.id] = tier,
      );

      // Null is not "unknown": it is what a pin-governed batch queues so the
      // destination resolves at download time.
      expect(tiers, <String, StorageTier?>{
        'a': StorageTier.appPrivate,
        'b': null,
      });
    });

    test('never runs more than the concurrency cap at once', () async {
      final FakeDownloadQueue queue = _queueOf(<String>[
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ]);
      int inFlight = 0;
      int peak = 0;
      final DrainDownloadQueue drain = DrainDownloadQueue(
        queue: queue,
        maxConcurrent: 2,
        perform:
            (
              Wallpaper wallpaper, {
              StorageTier? tier,
              TagFolder? tag,
            }) async {
              inFlight++;
              peak = peak > inFlight ? peak : inFlight;
              await Future<void>.delayed(const Duration(milliseconds: 5));
              inFlight--;
            },
      );

      await drain(paused: () => false, onSettled: () async {});

      expect(peak, 2);
      expect(await queue.entries(), isEmpty);
    });

    test(
      'marks a failure with its reason and leaves it in the queue',
      () async {
        final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);

        await _drain(
          queue,
          onDownload: (Wallpaper wallpaper) {
            if (wallpaper.id == 'a') {
              throw const ImageStoreFailure(ImageStoreProblem.source);
            }
          },
        );

        final List<QueuedDownload> left = await queue.entries();
        expect(left, hasLength(1));
        expect(left.single.ref.id, 'a');
        expect(left.single.state, DownloadQueueState.failed);
        expect(left.single.failure, ImageStoreProblem.source);
      },
    );

    test('does not retry a failure by itself', () async {
      // A queue that silently re-tries a 404 forever is worse than one that
      // says it could not: the retry is the user's tap, not the worker's.
      final FakeDownloadQueue queue = _queueOf(<String>['a']);
      int attempts = 0;

      await _drain(
        queue,
        onDownload: (Wallpaper wallpaper) {
          attempts++;
          throw const ImageStoreFailure(ImageStoreProblem.source);
        },
      );

      expect(attempts, 1);
    });

    test('treats a missing folder as a failure, not as a prompt', () async {
      // `ConfiguredDownload` answers notConfigured by opening the volume
      // chooser and retrying. A worker draining with no screen mounted cannot,
      // so it stops and says so — see DrainDownloadQueue._settle.
      final FakeDownloadQueue queue = _queueOf(<String>['a']);
      int attempts = 0;

      await _drain(
        queue,
        onDownload: (Wallpaper wallpaper) {
          attempts++;
          throw const ImageStoreFailure(ImageStoreProblem.notConfigured);
        },
      );

      final List<QueuedDownload> left = await queue.entries();
      expect(attempts, 1);
      expect(left.single.failure, ImageStoreProblem.notConfigured);
    });

    test('an unexpected error is a failure, not a crashed drain', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
      final List<String> downloaded = <String>[];

      await _drain(
        queue,
        onDownload: (Wallpaper wallpaper) {
          if (wallpaper.id == 'a') throw const FormatException('nonsense');
          downloaded.add(wallpaper.id);
        },
      );

      // 'b' still downloaded: one bad entry must not take the queue with it.
      expect(downloaded, <String>['b']);
      expect((await queue.entries()).single.failure, ImageStoreProblem.unknown);
    });

    test('stops claiming once paused, and leaves the rest queued', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b', 'c']);
      bool paused = false;
      final DrainDownloadQueue drain = DrainDownloadQueue(
        queue: queue,
        maxConcurrent: 1,
        perform:
            (
              Wallpaper wallpaper, {
              StorageTier? tier,
              TagFolder? tag,
            }) async {
              paused = true;
            },
      );

      await drain(paused: () => paused, onSettled: () async {});

      // The first entry ran and left; pausing mid-drain kept the other two.
      expect(await queue.entries(), hasLength(2));
    });

    test('reports each settled entry so a screen can follow along', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
      int settled = 0;

      await _drain(queue, onSettled: () async => settled++);

      expect(settled, 2);
    });
  });
}

/// Drains [queue] with a one-slot worker, so assertions read in order.
Future<void> _drain(
  FakeDownloadQueue queue, {
  void Function(Wallpaper wallpaper)? onDownload,
  void Function(Wallpaper wallpaper, StorageTier? tier)? onDownloadWithTier,
  Future<void> Function()? onSettled,
}) {
  final DrainDownloadQueue drain = DrainDownloadQueue(
    queue: queue,
    maxConcurrent: 1,
    perform:
        (
          Wallpaper wallpaper, {
          StorageTier? tier,
          TagFolder? tag,
        }) async {
          onDownload?.call(wallpaper);
          onDownloadWithTier?.call(wallpaper, tier);
        },
  );
  return drain(
    paused: () => false,
    onSettled: onSettled ?? () async {},
  );
}

FakeDownloadQueue _queueOf(List<String> ids) => FakeDownloadQueue(
  initial: <QueuedDownload>[
    for (final (int index, String id) in ids.indexed) _entry(id, at: index),
  ],
);

QueuedDownload _entry(String id, {StorageTier? tier, int at = 0}) =>
    QueuedDownload(
      wallpaper: _wallpaper(id),
      tier: tier,
      queuedAt: DateTime.utc(2026, 7, 26).add(Duration(seconds: at)),
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
