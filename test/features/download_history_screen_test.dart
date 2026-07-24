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
import 'package:tela/core/ui/gallery_session_controller.dart';
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
import '../fakes/fake_image_store.dart';

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

    testWidgets('wraps each tile in a cell-filling Stack', (
      WidgetTester tester,
    ) async {
      // The "lone history tile" anomaly: the grid blows a single download's
      // cell up to two thirds of the viewport, and a loose Stack let the
      // WallpaperTile fall back to its own decoded size and sit small in the
      // corner. StackFit.expand hands it the whole cell instead.
      //
      // Asserted structurally, not by measuring: reproducing the shrink needs a
      // really-decoded image at its memCacheWidth, which a widget test never
      // loads — the placeholder fills either way, so a size check passes even
      // with the bug present. The Stack's fit is the thing that actually moved.
      await _pump(
        tester,
        FakeDownloadHistory(
          initial: <DownloadRecord>[_landscapeDownload('k8')],
        ),
      );

      final Stack stack = tester.widget<Stack>(
        find
            .ancestor(
              of: find.byType(WallpaperTile),
              matching: find.byType(Stack),
            )
            .first,
      );
      expect(stack.fit, StackFit.expand);
    });

    testWidgets('a tap opens the viewer at the exact tapped record', (
      WidgetTester tester,
    ) async {
      // Newest first: index 0 is 'newer', index 1 is 'older'. Tapping the
      // second tile must open on it, not on index zero, and hand the viewer the
      // whole local history as one complete snapshot.
      GallerySessionController<DownloadRecord>? opened;
      await _pump(
        tester,
        FakeDownloadHistory(
          initial: <DownloadRecord>[_download('older'), _download('newer')],
        ),
        onOpen: (GallerySessionController<DownloadRecord> session) =>
            opened = session,
      );

      await tester.tap(find.byType(WallpaperTile).at(1));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.identity, 'download-history');
      expect(opened!.selectedIndex, 1);
      expect(opened!.selectedItem.wallpaper.id, 'older');
      expect(
        opened!.items.map((DownloadRecord d) => d.wallpaper.id),
        <String>['newer', 'older'],
      );
      expect(
        opened!.canRequestMore,
        isFalse,
        reason: 'History is a complete local snapshot and never pages',
      );
    });

    testWidgets('forgetting one row still says the file stays', (
      WidgetTester tester,
    ) async {
      // The wording *is* the feature. A history tile looks exactly like a file,
      // so a "remove" that does not say what it spares is how someone deletes
      // the wallpaper they meant to keep. D4 moved this behind multi-select —
      // the long press now ticks rather than asking — so this pins that the
      // sentence survived the move, at the count of one where it used to live.
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd')],
      );
      await _pump(tester, history);

      await _forgetSelected(tester);

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

      await _forgetSelected(tester);
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

      await _forgetSelected(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      // Only the one ticked (newest, '7j1mzo') is forgotten; 'e7jvjd'
      // remains. The grid refreshes without a relaunch — the stale-listing bug
      // of 2026-07-14 applies here too.
      expect(
        history.recorded.map((DownloadRecord d) => d.wallpaper.id),
        <String>['e7jvjd'],
      );
      expect(find.byType(WallpaperTile), findsOneWidget);
    });

    testWidgets('a batch delete says it deletes files, not rows', (
      WidgetTester tester,
    ) async {
      // The batch's two destructive actions sit side by side on one shelf, and
      // the only thing telling them apart before the tap lands is the sentence
      // — so it is pinned, exactly as the single forget's is above.
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd'), _download('7j1mzo')],
      );
      await _pump(tester, history);

      await _deleteSelected(tester);

      expect(find.text('Delete from device?'), findsOneWidget);
      expect(
        find.textContaining('deletes the file from your device'),
        findsOneWidget,
      );
      expect(history.recorded, hasLength(2));
    });

    testWidgets('a confirmed batch delete removes the files and the rows', (
      WidgetTester tester,
    ) async {
      final FakeImageStore imageStore = FakeImageStore();
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd'), _download('7j1mzo')],
      );
      await _pump(tester, history, imageStore: imageStore);

      await _deleteSelected(tester, count: 2);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // One batch, not one call per file: that is what keeps the gallery tier
      // to a single system prompt.
      expect(imageStore.batchSizes, <int>[2]);
      expect(history.recorded, isEmpty);
      expect(find.byType(WallpaperTile), findsNothing);
      expect(find.text('2 wallpapers deleted'), findsOneWidget);
    });

    testWidgets('a partly declined batch reports the honest tally', (
      WidgetTester tester,
    ) async {
      // A declined system prompt is not a failure, but it is not a deletion
      // either — "deleted 1 of 2" is the only true thing to say.
      final FakeImageStore imageStore = FakeImageStore(
        declined: <Uri>{_locationOf('e7jvjd')},
      );
      final FakeDownloadHistory history = FakeDownloadHistory(
        initial: <DownloadRecord>[_download('e7jvjd'), _download('7j1mzo')],
      );
      await _pump(tester, history, imageStore: imageStore);

      await _deleteSelected(tester, count: 2);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Deleted 1 of 2'), findsOneWidget);
      expect(
        history.recorded.map((DownloadRecord d) => d.wallpaper.id),
        <String>['e7jvjd'],
      );
    });

    testWidgets('returns to the same scrolled grid after the viewer', (
      WidgetTester tester,
    ) async {
      final List<DownloadRecord> many = List<DownloadRecord>.generate(
        30,
        (int index) => _download('item-$index'),
      );
      GallerySessionController<DownloadRecord>? opened;
      await _pump(
        tester,
        FakeDownloadHistory(initial: many),
        onOpen: (GallerySessionController<DownloadRecord> session) =>
            opened = session,
      );

      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      await tester.drag(find.byType(Scrollable), const Offset(0, -700));
      await tester.pumpAndSettle();
      final double before = scrollable.position.pixels;

      // Tiles are tall, so tap the visible band of a partially-visible one,
      // below the app bar and above the bottom edge.
      final Element visible = find.byType(WallpaperTile).evaluate().firstWhere((
        Element element,
      ) {
        final RenderBox box = element.renderObject! as RenderBox;
        final double y = box.localToGlobal(Offset.zero).dy;
        return y < 560 && y + box.size.height > 100;
      });
      final RenderBox box = visible.renderObject! as RenderBox;
      final Offset topLeft = box.localToGlobal(Offset.zero);
      final double top = topLeft.dy < 100 ? 100 : topLeft.dy;
      final double bottom = topLeft.dy + box.size.height;
      final double clampedBottom = bottom > 560 ? 560 : bottom;
      await tester.tapAt(
        Offset(topLeft.dx + box.size.width / 2, (top + clampedBottom) / 2),
      );
      await tester.pumpAndSettle();

      // The viewer opened, over the same scroll position it was tapped from.
      expect(opened, isNotNull);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(find.byType(DownloadHistoryScreen), findsOneWidget);
      expect(scrollable.position.pixels, before);
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
        imageStore: FakeImageStore(unreadable: <Uri>{_locationOf('7j1mzo')}),
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
  });
}

/// Boots the real screen over [history], behind a router so a tap can open the
/// viewer. History is an offline shelf, so no Wallhaven API is bound at all.
Future<void> _pump(
  WidgetTester tester,
  FakeDownloadHistory history, {
  FakeImageStore? imageStore,
  ValueChanged<GallerySessionController<DownloadRecord>>? onOpen,
}) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const DownloadHistoryScreen()),
      GoRoute(
        path: TelaRoutes.downloadViewerPath,
        name: TelaRoutes.downloadViewerName,
        builder: (_, GoRouterState state) {
          final GallerySessionController<DownloadRecord> session =
              state.extra! as GallerySessionController<DownloadRecord>;
          onOpen?.call(session);
          return Scaffold(body: Text(session.selectedItem.wallpaper.id));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        downloadHistoryProvider.overrideWithValue(history),
        // The grid probes each row's file to badge the ones that are gone.
        imageStoreProvider.overrideWithValue(imageStore ?? FakeImageStore()),
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

/// A landscape download (ratio 1.6), for the lone-cell fill test: a portrait
/// tile would fill the width first and never reach the sole-row ceiling.
DownloadRecord _landscapeDownload(String id) => DownloadRecord(
  wallpaper: Wallpaper(
    id: id,
    source: SourceId.wallhaven,
    pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
    fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
    resolution: const Resolution(2880, 1800),
    fileSizeBytes: 1024,
    purity: Purity.sfw,
    category: Category.general,
    colors: const <String>[],
  ),
  tier: StorageTier.sharedGallery,
  location: _locationOf(id),
  downloadedAt: DateTime(2026, 7, 14),
);

/// Long-presses the newest tile to enter selection, then taps *Remove*.
///
/// Stops at the confirmation rather than answering it, so each caller decides
/// what to do with the dialog. Extracted because all three forget tests walk
/// the identical two steps to reach it, and D4 is what made that walk long
/// enough to be worth naming.
Future<void> _forgetSelected(WidgetTester tester) async {
  await tester.longPress(find.byType(WallpaperTile).first);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.playlist_remove));
  await tester.pumpAndSettle();
}

/// Ticks the [count] newest tiles and taps *Delete from device*, stopping at
/// the confirmation for the caller to answer.
///
/// The hard delete's sibling of [_forgetSelected]: same walk, other action, and
/// it takes a count because the batch's whole point is more than one row.
Future<void> _deleteSelected(WidgetTester tester, {int count = 1}) async {
  await tester.longPress(find.byType(WallpaperTile).first);
  await tester.pumpAndSettle();
  for (int index = 1; index < count; index++) {
    await tester.tap(find.byType(WallpaperTile).at(index));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byIcon(Icons.delete_outline));
  await tester.pumpAndSettle();
}
