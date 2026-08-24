import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/drain_download_queue.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_download_queue.dart';
import '../fakes/fake_image_store.dart';

/// How often a draining queue re-reads the listings a landed download changes.
///
/// **The cost this measures is not the SQLite read.** Each refresh also sweeps
/// the private tier over the platform channel's single storage thread, and
/// recomputes the tile marks every shelf in the app is wearing. It fired once
/// per settled entry, three at a time — "the application seems to be sluggish
/// when downloading images on the background" (the owner, 2026-08-24).
void main() {
  testWidgets('a single download refreshes the listings at once', (
    WidgetTester tester,
  ) async {
    // The throttle is leading-edge, so nothing about the one-off case moved:
    // download one wallpaper and the History tab has it before you can reach
    // that tab. This is the promise the refresh was added for in the first
    // place (2026-07-14), and the one a naive debounce would have broken.
    final FakeDownloadHistory history = FakeDownloadHistory();
    await _drain(tester, ids: <String>['a'], history: history);

    expect(history.reads, 2, reason: 'the opening read, then the refresh');
  });

  testWidgets('a burst of downloads is read once, not once each', (
    WidgetTester tester,
  ) async {
    // Nine entries settling inside one window. Before the throttle this was
    // nine full listing reads plus nine private-tier sweeps plus nine
    // whole-app rebuilds; now the window's leading edge takes one and the
    // trailing edge takes the last.
    final FakeDownloadHistory history = FakeDownloadHistory();
    await _drain(
      tester,
      ids: <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'],
      history: history,
    );

    expect(
      history.reads,
      3,
      reason: 'the opening read, the window opening, and the window closing',
    );
  });

  testWidgets('the last download in a burst is never swallowed', (
    WidgetTester tester,
  ) async {
    // The half a throttle gets wrong if it only has a leading edge. A batch
    // whose final entry lands inside an open window would leave the History
    // tab one wallpaper short until something else happened to refresh it.
    final FakeDownloadHistory history = FakeDownloadHistory();
    final ProviderContainer container = await _drain(
      tester,
      ids: <String>['a', 'b', 'c'],
      history: history,
      record: true,
    );

    final List<DownloadRecord> shown = await container.read(
      recentDownloadsProvider.future,
    );
    expect(shown.length, 3);
  });
}

/// Drains a queue of [ids] to completion, with the refresh window run out.
///
/// A `testWidgets` rather than a `test` because the window is a real `Timer`
/// and only a tester's clock can be moved past it on purpose.
Future<ProviderContainer> _drain(
  WidgetTester tester, {
  required List<String> ids,
  required FakeDownloadHistory history,
  bool record = false,
}) async {
  final FakeDownloadQueue queue = FakeDownloadQueue(
    initial: <QueuedDownload>[
      for (final (int index, String id) in ids.indexed)
        QueuedDownload(
          wallpaper: _wallpaper(id),
          queuedAt: DateTime.utc(2026, 8, 24).add(Duration(seconds: index)),
        ),
    ],
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      downloadQueueProvider.overrideWithValue(queue),
      downloadHistoryProvider.overrideWithValue(history),
      imageStoreProvider.overrideWithValue(FakeImageStore()),
      drainDownloadQueueProvider.overrideWithValue(
        DrainDownloadQueue(
          queue: queue,
          perform: (Wallpaper wallpaper, {StorageTier? tier, TagFolder? tag}) =>
              _download(history, wallpaper, record: record),
          // One at a time, which is **not** what the app runs. The cap there
          // is three, and three entries finishing in the same tick are
          // coalesced into one listing read by Riverpod before this code is
          // reached — so a concurrent drain hides exactly the cadence under
          // test. Draining serially makes every settle its own turn, which is
          // the worst case the window has to hold.
          maxConcurrent: 1,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // A widget only so the tester has a clock to advance; nothing here is drawn.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const SizedBox.shrink(),
    ),
  );
  container
    // Kept alive, or an invalidated provider nobody watches never recomputes
    // and the reads this test counts would never happen.
    ..listen<AsyncValue<List<DownloadRecord>>>(
      recentDownloadsProvider,
      (_, _) {},
      fireImmediately: true,
    )
    ..read(downloadQueueControllerProvider);
  await tester.pump();
  // Stepped, not jumped. **The steps are the test**: a settle only costs a
  // listing read if it lands in its own turn of the event loop, and nine
  // downloads that all complete in the same microtask are coalesced by
  // Riverpod before this ever reaches the code under test. Real downloads take
  // hundreds of milliseconds each and arrive one at a time, which is the
  // shape this reproduces — an earlier version of this test jumped straight to
  // the end and passed with the throttle deleted.
  for (int step = 0; step < 40; step++) {
    await tester.pump(_downloadTime);
  }
  await tester.pump(DownloadQueueController.listingRefreshWindow * 2);
  return container;
}

/// How long one fake download takes. Short enough to keep the whole burst
/// inside one refresh window, long enough that each settle is its own turn.
const Duration _downloadTime = Duration(milliseconds: 20);

Future<void> _download(
  FakeDownloadHistory history,
  Wallpaper wallpaper, {
  required bool record,
}) async {
  await Future<void>.delayed(_downloadTime);
  if (!record) return;
  await history.record(
    wallpaper: wallpaper,
    tier: StorageTier.sharedGallery,
    location: Uri.parse('memory://${wallpaper.id}'),
  );
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
