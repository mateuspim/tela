import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/background_notice.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/offload_run.dart';
import 'package:tela/app/offload_run_controller.dart';
import 'package:tela/app/providers.dart';
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

import '../fakes/fake_download_queue.dart';
import '../fakes/fake_download_queue_anchor.dart';
import '../fakes/fake_image_store.dart';

void main() {
  _offloadTests();
  group('the notice rule', () {
    test('an owed queue anchors the process, naming the count', () async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _start(_queueOf(<String>['a', 'b', 'c']), anchor);

      expect(anchor.holds.last, 'Downloading wallpapers|3 left');
      expect(anchor.held, isTrue);
    });

    test('one owed download says so in the singular', () async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _start(_queueOf(<String>['a']), anchor);

      expect(anchor.holds.last, 'Downloading wallpapers|1 left');
    });

    test('an empty queue anchors nothing', () async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _start(FakeDownloadQueue(), anchor);

      expect(anchor.holds, isEmpty);
    });

    // Nothing is downloading, so there is nothing to protect from a low-memory
    // kill — and an ongoing notification for work that has stopped is a lie in
    // the one place the user cannot dismiss it.
    test('a paused queue drops the anchor even holding entries', () async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _start(
        _queueOf(<String>['a', 'b']),
        anchor,
      );
      expect(anchor.held, isTrue);

      container.read(downloadQueuePausedProvider.notifier).hold();
      await _settle();

      expect(anchor.held, isFalse);
      expect(anchor.releases, isNonZero);
    });

    // A queue of nothing but failures is waiting on the user, not on the
    // network, so keeping the process pinned for it buys nothing.
    test('a queue of only failures anchors nothing', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a']);
      await queue.markFailed(_wallpaper('a').ref, ImageStoreProblem.source);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _start(queue, anchor);

      expect(anchor.holds, isEmpty);
    });

    test('a failure beside live entries is not counted as owed', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b', 'c']);
      await queue.markFailed(_wallpaper('a').ref, ImageStoreProblem.source);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _start(queue, anchor);

      expect(anchor.holds.last, 'Downloading wallpapers|2 left');
    });
  });

  group('what reaches the platform', () {
    test('the count follows the queue down', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _start(queue, anchor);

      await container
          .read(downloadQueueControllerProvider.notifier)
          .cancel(_wallpaper('a').ref);
      await _settle();

      expect(anchor.holds.last, 'Downloading wallpapers|1 left');
    });

    test('emptying the queue drops the anchor', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _start(queue, anchor);

      await container
          .read(downloadQueueControllerProvider.notifier)
          .cancelAll();
      await _settle();

      // Not an exact count: the adapter is what drops repeats, which its own
      // test pins.
      expect(anchor.held, isFalse);
      expect(anchor.releases, isNonZero);
    });

    // A refused hold is Android's background-start restriction, not a failed
    // download. It must not stop the queue or reach the user as an error.
    test('a refused anchor leaves the queue alone', () async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor(
        refuses: true,
      );
      final ProviderContainer container = await _start(queue, anchor);

      expect(anchor.holds, isNotEmpty);
      expect(
        container.read(downloadQueueControllerProvider).value,
        hasLength(2),
      );
    });
  });

  // The notification's words are the ARB's, resolved with no BuildContext —
  // which is the whole reason the notice can live outside the widget tree.
  test('the shade reads its words from the ARB', () {
    expect(shadeWords().downloadQueueNoticeTitle, 'Downloading wallpapers');
    expect(shadeWords().downloadQueueNoticeBody(4), '4 left');
  });
}

/// Boots the notice over [queue] with its downloads held mid-flight.
///
/// **No widget, and that is the point.** The anchor has to keep reporting after
/// the activity — and every frame with it — is gone, so it hangs off the
/// container rather than a `build`. Nothing here pumps anything.
///
/// **It cannot use `pause` to freeze the line, the way the queue tab's tests
/// do** — pausing is one of the things being asserted, and it drops the anchor
/// by design. So the drain itself is replaced with one whose downloads never
/// settle: entries are claimed and stay claimed, which leaves the count still
/// owed and stable under the assertions, and is what a real batch looks like
/// while it runs.
Future<ProviderContainer> _start(
  FakeDownloadQueue queue,
  FakeDownloadQueueAnchor anchor,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      downloadQueueProvider.overrideWithValue(queue),
      downloadQueueAnchorProvider.overrideWithValue(anchor),
      imageStoreProvider.overrideWithValue(FakeImageStore()),
      drainDownloadQueueProvider.overrideWithValue(
        DrainDownloadQueue(
          queue: queue,
          perform: (Wallpaper wallpaper, {StorageTier? tier, TagFolder? tag}) =>
              Completer<void>().future,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  anchorBackgroundWork(container);
  await _settle();
  return container;
}

/// The offload's own claim on the same anchor.
///
/// One notification, one service, so the two kinds of background work cannot
/// each hold it: the offload wins while it runs, and the queue takes the shade
/// back when it is over.
void _offloadTests() {
  group('the offload shares the anchor', () {
    test('a running offload takes the shade from the queue', () async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _start(
        _queueOf(<String>['a', 'b', 'c']),
        anchor,
      );
      expect(anchor.holds.last, 'Downloading wallpapers|3 left');

      await _publish(container, OffloadPhase.copying, total: 4, copied: 1);

      expect(anchor.holds.last, 'Move downloads to SD card|Moving 1 of 4…');
    });

    /// The phase where the shade is the only place left to say anything: the
    /// copy is done, the app is away, and the OS delete prompt needs a screen.
    test('a run waiting for a screen says so in the shade', () async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _start(
        FakeDownloadQueue(),
        anchor,
      );

      await _publish(
        container,
        OffloadPhase.waitingForScreen,
        total: 4,
        copied: 4,
      );

      expect(anchor.holds.last, contains('Come back to tela'));
    });

    test('a finished run hands the shade back to the queue', () async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _start(
        _queueOf(<String>['a']),
        anchor,
      );
      await _publish(container, OffloadPhase.copying);
      await _publish(container, OffloadPhase.done);

      expect(anchor.holds.last, 'Downloading wallpapers|1 left');
    });

    test('a finished run with nothing queued drops the anchor', () async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _start(
        FakeDownloadQueue(),
        anchor,
      );
      await _publish(container, OffloadPhase.copying);
      expect(anchor.held, isTrue);

      await _publish(container, OffloadPhase.done);

      expect(anchor.held, isFalse);
    });
  });
}

/// Publishes a run in [phase] and lets the shade catch up.
///
/// The controller's own `start` is not used here: these tests are about what
/// the *notice* makes of a run, and driving a real move through them would put
/// a storage fake between the assertion and the thing being asserted.
Future<void> _publish(
  ProviderContainer container,
  OffloadPhase phase, {
  int total = 1,
  int copied = 0,
}) async {
  container.read(offloadRunProvider.notifier).state = OffloadRun(
    phase: phase,
    total: total,
    copied: copied,
  );
  await _settle();
}

/// Lets the queue's own futures and Riverpod's refresh timer run.
///
/// Timers, not frames: nothing is pumped here because there is nothing to pump.
/// Riverpod refreshes a derived provider on a zero-duration timer when no
/// mounted scope offers it a vsync — which is exactly the state the app is in
/// once its activity is destroyed, and why the anchor keeps working there.
Future<void> _settle() => pumpEventQueue();

FakeDownloadQueue _queueOf(List<String> ids) => FakeDownloadQueue(
  initial: <QueuedDownload>[
    for (final (int index, String id) in ids.indexed)
      QueuedDownload(
        wallpaper: _wallpaper(id),
        queuedAt: DateTime.utc(2026, 7, 26).add(Duration(seconds: index)),
      ),
  ],
);

Wallpaper _wallpaper(String id, {Purity purity = Purity.sfw}) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/xx/wallhaven-$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/xx/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/xx/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/xx/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
