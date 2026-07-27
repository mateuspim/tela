import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/downloads/download_queue_tab.dart';
import 'package:tela/features/private_library/private_unlock_session.dart';

import '../fakes/fake_download_queue.dart';
import '../fakes/fake_image_store.dart';

void main() {
  testWidgets('an empty queue says what the screen is for', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeDownloadQueue());

    expect(find.textContaining('Nothing waiting'), findsOneWidget);
  });

  testWidgets('a paused queue says so on the count itself', (
    WidgetTester tester,
  ) async {
    // A paused queue and a stalled one look identical without this.
    final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
    await _pump(tester, queue, paused: true);

    expect(find.text('2 downloads left · paused'), findsOneWidget);
  });

  testWidgets('failures are counted beside what is still owed', (
    WidgetTester tester,
  ) async {
    // "2 left" over a failure is the aggregate lie: that wallpaper is not
    // coming without the user acting.
    final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
    await queue.markFailed(_wallpaper('a').ref, ImageStoreProblem.source);
    await _pump(tester, queue, paused: true);

    expect(find.text('1 left · 1 failed'), findsOneWidget);
  });

  testWidgets('a failed entry names its reason and its attempts', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = FakeDownloadQueue(
      initial: <QueuedDownload>[
        QueuedDownload(
          wallpaper: _wallpaper('a'),
          queuedAt: DateTime.utc(2026, 7, 26),
          state: DownloadQueueState.failed,
          attempts: 2,
          failure: ImageStoreProblem.folderUnavailable,
        ),
      ],
    );
    await _pump(tester, queue, paused: true);

    expect(
      find.text('Reconnect the storage it saves to · 2 tries'),
      findsOneWidget,
    );
  });

  testWidgets('Retry puts one failed entry back in line', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = _queueOf(<String>['a']);
    await queue.markFailed(_wallpaper('a').ref, ImageStoreProblem.source);
    await _pump(tester, queue, paused: true);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    final QueuedDownload entry = (await queue.entries()).single;
    expect(entry.state, DownloadQueueState.pending);
    expect(entry.failure, isNull);
  });

  testWidgets('Retry all moves every failure at once', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
    await queue.markFailed(_wallpaper('a').ref, ImageStoreProblem.source);
    await queue.markFailed(_wallpaper('b').ref, ImageStoreProblem.source);
    await _pump(tester, queue, paused: true);

    await tester.tap(find.text('Retry all'));
    await tester.pumpAndSettle();

    expect(
      (await queue.entries()).every(
        (QueuedDownload e) => e.state == DownloadQueueState.pending,
      ),
      isTrue,
    );
  });

  testWidgets('Retry all is offered only when something has failed', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _queueOf(<String>['a']), paused: true);

    expect(find.text('Retry all'), findsNothing);
  });

  testWidgets('removing an entry takes it out of the line', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
    await _pump(tester, queue, paused: true);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect((await queue.entries()).single.ref.id, 'b');
  });

  testWidgets('emptying the queue drops every entry', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = _queueOf(<String>['a', 'b']);
    await _pump(tester, queue, paused: true);

    await tester.tap(find.byIcon(Icons.clear_all));
    await tester.pumpAndSettle();

    expect(await queue.entries(), isEmpty);
  });

  testWidgets('Pause stops the queue, and Resume picks it back up', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = _queueOf(<String>['a']);
    final ProviderContainer container = await _pump(
      tester,
      queue,
      paused: true,
    );

    // Starts paused here so nothing drains under the assertions; the button is
    // the Resume half, and tapping it must clear the flag.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(container.read(downloadQueuePausedProvider), isFalse);
  });

  testWidgets('an explicit entry is not identified while locked', (
    WidgetTester tester,
  ) async {
    // The queue may hold one — refusing would silently decline a download the
    // user asked for — but this tab sits behind no app-lock and no FLAG_SECURE,
    // so a thumbnail and an id on it would be the ungated index the private
    // tier exists to prevent.
    final FakeDownloadQueue queue = FakeDownloadQueue(
      initial: <QueuedDownload>[
        QueuedDownload(
          wallpaper: _wallpaper('a', purity: Purity.nsfw),
          queuedAt: DateTime.utc(2026, 7, 26),
        ),
      ],
    );
    await _pump(tester, queue, paused: true);

    expect(find.text('Private download'), findsOneWidget);
    expect(find.text('a'), findsNothing);
    // It still counts and still offers its controls — only the identifying
    // half is withheld.
    expect(find.text('1 download left · paused'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('an explicit entry is named once the library is unlocked', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = FakeDownloadQueue(
      initial: <QueuedDownload>[
        QueuedDownload(
          wallpaper: _wallpaper('a', purity: Purity.nsfw),
          queuedAt: DateTime.utc(2026, 7, 26),
        ),
      ],
    );
    await _pump(tester, queue, paused: true, unlocked: true);

    expect(find.text('a'), findsOneWidget);
    expect(find.text('Private download'), findsNothing);
  });

  testWidgets('a safe entry is named without any unlock', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _queueOf(<String>['a']), paused: true);

    expect(find.text('a'), findsOneWidget);
  });
}

/// Boots the tab over [queue], with the drain held off unless a test wants it.
///
/// [paused] is how a test freezes the line: the controller starts draining the
/// moment it builds, and a queue that empties itself has nothing left to assert
/// about. [unlocked] stands in for the private library's app-lock having been
/// satisfied this session.
///
/// Both flags are set on the container **before** the tree is pumped. Riverpod
/// forbids writing a provider from a widget life-cycle, so setting them from a
/// `Consumer.builder` throws — and the tab renders the unpaused, locked state
/// anyway, which is the opposite of what the test asked for.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeDownloadQueue queue, {
  bool paused = false,
  bool unlocked = false,
}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      downloadQueueProvider.overrideWithValue(queue),
      imageStoreProvider.overrideWithValue(FakeImageStore()),
    ],
  );
  addTearDown(container.dispose);
  if (paused) container.read(downloadQueuePausedProvider.notifier).hold();
  if (unlocked) container.read(privateUnlockSessionProvider.notifier).grant();
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
        home: Scaffold(body: DownloadQueueTab()),
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
