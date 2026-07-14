import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/downloads/download_history_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_wallpaper_applier.dart';

void main() {
  group('DownloadHistoryScreen', () {
    testWidgets('explains itself when nothing has been downloaded', (
      WidgetTester tester,
    ) async {
      await _pump(tester, FakeDownloadHistory());

      expect(find.textContaining('Nothing downloaded yet'), findsOneWidget);
      expect(find.byType(WallpaperTile), findsNothing);
    });

    testWidgets('renders a tile per download, newest first', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeDownloadHistory(
          initial: <DownloadRecord>[_download('older'), _download('newer')],
        ),
      );

      final Iterable<WallpaperTile> tiles = tester.widgetList<WallpaperTile>(
        find.byType(WallpaperTile),
      );
      expect(
        tiles.map((WallpaperTile tile) => tile.wallpaper.id),
        <String>['newer', 'older'],
      );
    });

    testWidgets('sets a download again from the file, not from Wallhaven', (
      WidgetTester tester,
    ) async {
      final FakeWallpaperApplier applier = FakeWallpaperApplier();
      await _pump(
        tester,
        FakeDownloadHistory(initial: <DownloadRecord>[_download('e7jvjd')]),
        applier: applier,
      );

      await tester.tap(find.byType(WallpaperTile));
      await tester.pumpAndSettle();
      expect(find.text('Set wallpaper on'), findsOneWidget);

      await tester.tap(find.text('Home and lock screens'));
      await tester.pumpAndSettle();

      expect(applier.receivedSources, <Uri>[_locationOf('e7jvjd')]);
      expect(applier.receivedTarget, WallpaperTarget.both);
      expect(find.text('Wallpaper set.'), findsOneWidget);
    });

    testWidgets('a long press offers to forget the row, and says the file '
        'stays', (WidgetTester tester) async {
      // The wording *is* the feature. A history tile looks exactly like a file,
      // so a "remove" that does not say what it spares is how someone deletes
      // the wallpaper they meant to keep.
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd')],
      );
      await _pump(tester, history);

      await tester.longPress(find.byType(WallpaperTile));
      await tester.pumpAndSettle();

      expect(find.text('Remove from history?'), findsOneWidget);
      expect(
        find.textContaining('The wallpaper file stays where it was downloaded'),
        findsOneWidget,
      );
      // Nothing happens until it is confirmed.
      expect(history.recorded, hasLength(1));
    });

    testWidgets('cancelling a forget keeps the row', (
      WidgetTester tester,
    ) async {
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd')],
      );
      await _pump(tester, history);

      await tester.longPress(find.byType(WallpaperTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(history.recorded, hasLength(1));
      expect(find.byType(WallpaperTile), findsOneWidget);
    });

    testWidgets('confirming forgets the row and drops the tile', (
      WidgetTester tester,
    ) async {
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd'), _download('7j1mzo')],
      );
      await _pump(tester, history);

      await tester.longPress(find.byType(WallpaperTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      // Only the one long-pressed is forgotten, and the grid refreshes without
      // a relaunch — the stale-listing bug of 2026-07-14 applies here too.
      expect(
        history.recorded.map((DownloadRecord d) => d.wallpaper.id),
        <String>['e7jvjd'],
      );
      expect(find.byType(WallpaperTile), findsOneWidget);
    });
  });

  group('a download whose file is gone', () {
    testWidgets('is badged, and says so to a screen reader too', (
      WidgetTester tester,
    ) async {
      // tela is never told when a file it wrote is deleted from Photos or a
      // file manager, so the history would otherwise keep calling it
      // "wallpapers already on this device" and quietly charge a re-download on
      // tap. The tile says which rows those are, before you tap them.
      await _pump(
        tester,
        FakeDownloadHistory(
          initial: <DownloadRecord>[_download('e7jvjd'), _download('7j1mzo')],
        ),
        imageStore: FakeImageStore(
          unreadable: <Uri>{_locationOf('7j1mzo')},
        ),
      );

      expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
      // The badge is visual; the label must carry the same distinction.
      expect(
        find.bySemanticsLabel('Download 7j1mzo again and set it'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Set wallpaper e7jvjd again'),
        findsOneWidget,
      );
    });

    testWidgets('still sets, and no tile is badged when every file is there', (
      WidgetTester tester,
    ) async {
      final FakeWallpaperApplier applier = FakeWallpaperApplier();
      await _pump(
        tester,
        FakeDownloadHistory(initial: <DownloadRecord>[_download('e7jvjd')]),
        applier: applier,
      );

      expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);

      await tester.tap(find.byType(WallpaperTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home and lock screens'));
      await tester.pumpAndSettle();

      expect(applier.receivedSources, <Uri>[_locationOf('e7jvjd')]);
    });
  });
}

/// Boots the real screen over [history], with no API bound at all: the history
/// is an offline shelf, and needing Wallhaven to draw it would defeat it.
Future<void> _pump(
  WidgetTester tester,
  FakeDownloadHistory history, {
  FakeWallpaperApplier? applier,
  FakeImageStore? imageStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        downloadHistoryProvider.overrideWithValue(history),
        wallpaperApplierProvider.overrideWithValue(
          applier ?? FakeWallpaperApplier(),
        ),
        // The grid probes each row's file to badge the ones that are gone.
        imageStoreProvider.overrideWithValue(imageStore ?? FakeImageStore()),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: DownloadHistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Uri _locationOf(String id) =>
    Uri.parse('content://media/external/images/media/$id');

DownloadRecord _download(String id) => DownloadRecord(
  wallpaper: Wallpaper(
    id: id,
    fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
    resolution: const Resolution(1080, 2400),
    fileSizeBytes: 1024,
    purity: Purity.sfw,
    category: Category.general,
    colors: const <String>[],
  ),
  tier: StorageTier.sharedGallery,
  location: _locationOf(id),
  downloadedAt: DateTime(2026, 7, 14),
);
