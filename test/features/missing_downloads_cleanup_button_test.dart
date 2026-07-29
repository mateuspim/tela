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
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/downloads/download_history_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_download_queue.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_settings_repository.dart';

void main() {
  group('MissingDownloadsCleanupButton', () {
    testWidgets('hidden when nothing has lost its file', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeDownloadHistory(initial: <DownloadRecord>[_download('e7jvjd')]),
      );

      expect(
        find.byIcon(Icons.cleaning_services_outlined),
        findsNothing,
      );
    });

    testWidgets('names how many rows are missing their file', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        FakeDownloadHistory(
          initial: <DownloadRecord>[_download('e7jvjd'), _download('7j1mzo')],
        ),
        imageStore: FakeImageStore(unreadable: <Uri>{_locationOf('7j1mzo')}),
      );

      await tester.tap(find.byIcon(Icons.cleaning_services_outlined));
      await tester.pumpAndSettle();

      expect(find.text('1 download lost its file'), findsOneWidget);
    });

    testWidgets('cancelling leaves the rows untouched', (
      WidgetTester tester,
    ) async {
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('7j1mzo')],
      );
      await _pump(
        tester,
        history,
        imageStore: FakeImageStore(unreadable: <Uri>{_locationOf('7j1mzo')}),
      );

      await tester.tap(find.byIcon(Icons.cleaning_services_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(history.recorded, hasLength(1));
      expect(find.byType(WallpaperTile), findsOneWidget);
    });

    testWidgets('delete reaches only the missing rows, not the whole history', (
      WidgetTester tester,
    ) async {
      // Two rows, one missing: the cleanup dialog must hand exactly that one
      // to the batch delete, or a cleanup meant for stale rows would also
      // reach a wallpaper whose file is fine.
      final FakeImageStore imageStore = FakeImageStore(
        unreadable: <Uri>{_locationOf('7j1mzo')},
      );
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd'), _download('7j1mzo')],
      );
      await _pump(tester, history, imageStore: imageStore);

      await tester.tap(find.byIcon(Icons.cleaning_services_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete rows'));
      await tester.pumpAndSettle();

      // The batch delete's own confirmation still guards the file loss —
      // this dialog only chooses which fate, it does not itself confirm one.
      expect(find.text('Delete from device?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(imageStore.batchSizes, <int>[1]);
      expect(
        history.recorded.map((DownloadRecord d) => d.wallpaper.id),
        <String>['e7jvjd'],
      );
      expect(find.byType(WallpaperTile), findsOneWidget);
    });

    testWidgets('redownload reaches only the missing rows', (
      WidgetTester tester,
    ) async {
      // The fake queue drains instantly, so the entry is already gone by the
      // time a widget test could inspect it — same reason the browse suite's
      // own success case reads the toast rather than the queue. What proves
      // the redownload actually reached only the missing row is the
      // destination chooser's count, and the untouched row surviving
      // unduplicated in history afterwards.
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd'), _download('7j1mzo')],
      );
      await _pump(
        tester,
        history,
        imageStore: FakeImageStore(unreadable: <Uri>{_locationOf('7j1mzo')}),
      );

      await tester.tap(find.byIcon(Icons.cleaning_services_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redownload all'));
      await tester.pumpAndSettle();

      // Named "1", not "2": only the missing row went to the destination
      // chooser, same as the delete path above.
      expect(find.text('Download 1 wallpaper to'), findsOneWidget);
      await tester.tap(find.text('Gallery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Queued 1 wallpaper'), findsOneWidget);
      expect(
        history.recorded.map((DownloadRecord d) => d.wallpaper.id).toSet(),
        <String>{'e7jvjd', '7j1mzo'},
      );
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeDownloadHistory history, {
  FakeImageStore? imageStore,
  FakeDownloadQueue? queue,
}) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const DownloadHistoryScreen()),
      GoRoute(
        path: TelaRoutes.downloadViewerPath,
        name: TelaRoutes.downloadViewerName,
        builder: (_, GoRouterState state) => const Scaffold(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        downloadHistoryProvider.overrideWithValue(history),
        imageStoreProvider.overrideWithValue(imageStore ?? FakeImageStore()),
        downloadQueueProvider.overrideWithValue(queue ?? FakeDownloadQueue()),
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
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
  ),
  tier: StorageTier.sharedGallery,
  location: _locationOf(id),
  downloadedAt: DateTime(2026, 7, 14),
);
