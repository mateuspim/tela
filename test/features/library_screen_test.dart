import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/downloads/recent_downloads_strip.dart';
import 'package:tela/features/favorites/favorites_grid.dart';
import 'package:tela/features/library/library_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_favorites_repository.dart';

/// D2b — Library as a hub of sections rather than a list of doors.
void main() {
  testWidgets('the hub previews downloads and embeds the favorites shelf', (
    WidgetTester tester,
  ) async {
    await _pumpLibrary(tester, downloads: <DownloadRecord>[_record('a')]);

    expect(find.text('RECENT DOWNLOADS'), findsOneWidget);
    expect(find.byType(RecentDownloadsStrip), findsOneWidget);
    // The private tier keeps its plain locked row and gets no preview strip —
    // the hub sits behind no app-lock, so thumbnails here would disclose
    // exactly what that tier exists to hide.
    expect(find.text('Private library'), findsOneWidget);
    expect(find.byType(FavoritesGrid), findsOneWidget);
  });

  testWidgets('a long press on the downloads strip starts selecting there', (
    WidgetTester tester,
  ) async {
    // The strip had no long press at all, so batching your downloads meant
    // reaching *See all* first while the favorites shelf a few dips below
    // selected in place (owner, 2026-07-19).
    await _pumpLibrary(tester, downloads: <DownloadRecord>[_record('a')]);

    await tester.longPress(find.byType(WallpaperTile).first);
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('viewer-screen'), findsNothing);
  });

  testWidgets("the hub's two shelves select independently of each other", (
    WidgetTester tester,
  ) async {
    // One selection for the whole screen would let a download and a favorite
    // land in the same batch, over two shelves that offer different actions.
    // So each section owns its own scope, and ticking in one leaves the other
    // alone — including its *Select* button, which stays offered.
    await _pumpLibrary(
      tester,
      downloads: <DownloadRecord>[_record('a')],
      favorites: <Wallpaper>[_record('b').wallpaper],
    );

    await tester.longPress(find.byType(WallpaperTile).first);
    await tester.pumpAndSettle();

    // Exactly one bar, and the other shelf never entered the mode.
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.checklist), findsOneWidget);
  });

  testWidgets('the strip replaced the history row, and See all leads there', (
    WidgetTester tester,
  ) async {
    // A row and a strip both meaning "downloads" would be two affordances for
    // one idea, so the text row is gone and the section header carries the way
    // through to the full history.
    await _pumpLibrary(tester, downloads: <DownloadRecord>[_record('a')]);

    expect(find.text('Download history'), findsNothing);

    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();

    expect(find.text('history-screen'), findsOneWidget);
  });

  testWidgets('the strip shows the newest downloads, newest first', (
    WidgetTester tester,
  ) async {
    await _pumpLibrary(
      tester,
      downloads: <DownloadRecord>[_record('older'), _record('newer')],
    );

    final Iterable<WallpaperTile> tiles = tester.widgetList<WallpaperTile>(
      find.descendant(
        of: find.byType(RecentDownloadsStrip),
        matching: find.byType(WallpaperTile),
      ),
    );
    expect(
      tiles.map((WallpaperTile tile) => tile.wallpaper.id),
      <String>['newer', 'older'],
    );
  });

  testWidgets('tapping a preview opens the viewer on that download', (
    WidgetTester tester,
  ) async {
    await _pumpLibrary(tester, downloads: <DownloadRecord>[_record('a')]);

    await tester.tap(
      find.descendant(
        of: find.byType(RecentDownloadsStrip),
        matching: find.byType(WallpaperTile),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('viewer-screen'), findsOneWidget);
  });

  testWidgets('an empty history still offers the way into it', (
    WidgetTester tester,
  ) async {
    // The strip is the entry point now, so a hub with nothing to preview must
    // not become a hub with no downloads section at all.
    await _pumpLibrary(tester, downloads: const <DownloadRecord>[]);

    expect(find.text('RECENT DOWNLOADS'), findsOneWidget);
    expect(find.textContaining('Nothing downloaded yet'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('the private entry opens the private library', (
    WidgetTester tester,
  ) async {
    await _pumpLibrary(tester, downloads: const <DownloadRecord>[]);

    await tester.tap(find.text('Private library'));
    await tester.pumpAndSettle();

    expect(find.text('private-screen'), findsOneWidget);
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required List<DownloadRecord> downloads,
  List<Wallpaper> favorites = const <Wallpaper>[],
}) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
      _stub(
        TelaRoutes.downloadHistoryPath,
        TelaRoutes.downloadHistoryName,
        'history-screen',
      ),
      _stub(
        TelaRoutes.privateLibraryPath,
        TelaRoutes.privateLibraryName,
        'private-screen',
      ),
      _stub(
        TelaRoutes.downloadViewerPath,
        TelaRoutes.downloadViewerName,
        'viewer-screen',
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(initial: favorites),
        ),
        downloadHistoryProvider.overrideWithValue(
          FakeDownloadHistory(initial: downloads),
        ),
      ],
      child: MaterialApp.router(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

GoRoute _stub(String path, String name, String label) => GoRoute(
  path: path,
  name: name,
  builder: (_, _) => Scaffold(body: Center(child: Text(label))),
);

DownloadRecord _record(String id) => DownloadRecord(
  wallpaper: Wallpaper(
    id: id,
    fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-$id.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/$id.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/$id.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/$id.jpg',
    resolution: const Resolution(2560, 1440),
    fileSizeBytes: 2048,
    purity: Purity.sfw,
    category: Category.general,
    colors: const <String>[],
  ),
  tier: StorageTier.sharedGallery,
  location: Uri.parse('file:///pictures/tela/$id.jpg'),
  downloadedAt: DateTime(2026, 7, 19),
);
