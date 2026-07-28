import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/download_queue_notice.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/drain_download_queue.dart';

import '../fakes/fake_download_queue.dart';
import '../fakes/fake_download_queue_anchor.dart';
import '../fakes/fake_image_store.dart';

void main() {
  group('the notice rule', () {
    testWidgets('an owed queue anchors the process, naming the count', (
      WidgetTester tester,
    ) async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _pump(tester, _queueOf(<String>['a', 'b', 'c']), anchor);

      expect(anchor.holds.last, 'Downloading wallpapers|3 left');
      expect(anchor.held, isTrue);
    });

    testWidgets('one owed download says so in the singular', (
      WidgetTester tester,
    ) async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _pump(tester, _queueOf(<String>['a']), anchor);

      expect(anchor.holds.last, 'Downloading wallpapers|1 left');
    });

    testWidgets('an empty queue anchors nothing', (WidgetTester tester) async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _pump(tester, FakeDownloadQueue(), anchor);

      expect(anchor.holds, isEmpty);
    });

    // Nothing is downloading, so there is nothing to protect from a low-memory
    // kill — and an ongoing notification for work that has stopped is a lie in
    // the one place the user cannot dismiss it.
    testWidgets('a paused queue drops the anchor even holding entries', (
      WidgetTester tester,
    ) async {
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _pump(
        tester,
        _queueOf(<String>['a', 'b']),
        anchor,
      );
      expect(anchor.held, isTrue);

      container.read(downloadQueuePausedProvider.notifier).hold();
      await tester.pumpAndSettle();

      // Not an exact count: the notice re-announces on every rebuild and it is
      // the adapter that drops the repeats, which its own test pins.
      expect(anchor.held, isFalse);
      expect(anchor.releases, isNonZero);
    });

    // A queue of nothing but failures is waiting on the user, not on the
    // network, so keeping the process pinned for it buys nothing.
    testWidgets('a queue of only failures anchors nothing', (
      WidgetTester tester,
    ) async {
      final FakeDownloadQueue queue = _queueOf(<String>['a']);
      await queue.markFailed(_wallpaper('a').ref, ImageStoreProblem.source);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _pump(tester, queue, anchor);

      expect(anchor.holds, isEmpty);
    });

    testWidgets('a failure beside live entries is not counted as owed', (
      WidgetTester tester,
    ) async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b', 'c']);
      await queue.markFailed(_wallpaper('a').ref, ImageStoreProblem.source);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      await _pump(tester, queue, anchor);

      expect(anchor.holds.last, 'Downloading wallpapers|2 left');
    });
  });

  group('what reaches the platform', () {
    // The notice re-announces on every rebuild by design; the dedupe lives in
    // the adapter. What must never happen is a *count* that stops updating,
    // which is what a rebuild-only announcement would give.
    testWidgets('the count follows the queue down', (
      WidgetTester tester,
    ) async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _pump(tester, queue, anchor);

      await container
          .read(downloadQueueControllerProvider.notifier)
          .cancel(_wallpaper('a').ref);
      await tester.pumpAndSettle();

      expect(anchor.holds.last, 'Downloading wallpapers|1 left');
    });

    testWidgets('emptying the queue drops the anchor', (
      WidgetTester tester,
    ) async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor();
      final ProviderContainer container = await _pump(tester, queue, anchor);

      await container
          .read(downloadQueueControllerProvider.notifier)
          .cancelAll();
      await tester.pumpAndSettle();

      // Not an exact count: the notice re-announces on every rebuild and it is
      // the adapter that drops the repeats, which its own test pins.
      expect(anchor.held, isFalse);
      expect(anchor.releases, isNonZero);
    });

    // A refused hold is Android's background-start restriction, not a failed
    // download. It must not stop the queue or reach the user as an error.
    testWidgets('a refused anchor leaves the queue alone', (
      WidgetTester tester,
    ) async {
      final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
      final FakeDownloadQueueAnchor anchor = FakeDownloadQueueAnchor(
        refuses: true,
      );
      final ProviderContainer container = await _pump(tester, queue, anchor);

      expect(anchor.holds, isNotEmpty);
      expect(
        container.read(downloadQueueControllerProvider).value,
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Boots the notice over [queue] with its downloads held mid-flight.
///
/// **It cannot use `pause` to freeze the line, the way the queue tab's tests
/// do** — pausing is one of the things being asserted, and it drops the anchor
/// by design. So the drain itself is replaced with one whose downloads never
/// settle: entries are claimed and stay claimed, which leaves the count still
/// owed and stable under the assertions, and is what a real batch looks like
/// while it runs.
///
/// The notice renders nothing of its own, so there is no widget to find — every
/// assertion here is about what crossed to [anchor]. It is mounted under a
/// `MaterialApp` because the notification's words come from the ARB, which
/// needs the localizations delegate above it.
Future<ProviderContainer> _pump(
  WidgetTester tester,
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
          perform: (Wallpaper wallpaper, {StorageTier? tier}) =>
              Completer<void>().future,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: DownloadQueueNotice(child: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

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
