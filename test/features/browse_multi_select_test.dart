import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_download_queue.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// D4 — selecting several wallpapers on the wall and acting on them at once.
///
/// Entry is through D1's quick sheet rather than by taking the long press
/// over, because the two are the same gesture and deciding that twice is how
/// they end up fighting.
void main() {
  testWidgets('the quick sheet offers to start selecting', (
    WidgetTester tester,
  ) async {
    await _pumpWall(tester);

    await _longPressTile(tester, 0);

    expect(find.text('Select wallpapers'), findsOneWidget);
  });

  testWidgets(
    'selecting from the sheet enters the mode with that tile ticked',
    (WidgetTester tester) async {
      await _pumpWall(tester);

      await _startSelecting(tester);

      expect(find.text('1 selected'), findsOneWidget);
    },
  );

  testWidgets('while selecting, a tap ticks instead of opening the wallpaper', (
    WidgetTester tester,
  ) async {
    // The load-bearing half of the mode. A shelf that kept its open-on-tap
    // would send the user to the detail screen every time they tried to add a
    // second wallpaper to the batch.
    await _pumpWall(tester);
    await _startSelecting(tester);

    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byType(WallpaperDetailScreen), findsNothing);
  });

  testWidgets('unticking the last tile keeps the mode, and X leaves it', (
    WidgetTester tester,
  ) async {
    await _pumpWall(tester);
    await _startSelecting(tester);

    await tester.tap(find.byType(WallpaperTile).first);
    await _settle(tester);

    // Still selecting, just empty — the mode is explicit since the app-bar
    // Select button landed, so a stray tap cannot end it.
    expect(find.text('None selected'), findsOneWidget);
    expect(find.byType(WallpaperDetailScreen), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await _settle(tester);

    // And the wall is a wall again: the next tap opens the wallpaper.
    await tester.tap(find.byType(WallpaperTile).first);
    await _settle(tester);
    expect(find.byType(WallpaperDetailScreen), findsOneWidget);
  });

  testWidgets('the app bar offers Select without any tile being pressed', (
    WidgetTester tester,
  ) async {
    // The discoverable way in. The long press and the quick sheet's row are
    // shortcuts for people who already know the mode exists.
    await _pumpWall(tester);

    await tester.tap(find.byIcon(Icons.checklist));
    await _settle(tester);

    expect(find.text('None selected'), findsOneWidget);
  });

  testWidgets('select all ticks every wallpaper on the shelf', (
    WidgetTester tester,
  ) async {
    await _pumpWall(tester);
    await _startSelecting(tester);

    await tester.tap(find.byIcon(Icons.select_all));
    await _settle(tester);

    expect(find.text('3 selected'), findsOneWidget);
  });

  testWidgets('back leaves selection mode rather than the screen', (
    WidgetTester tester,
  ) async {
    // The gesture everyone tries first to undo a selection. Without the
    // PopScope it costs them the shelf instead.
    await _pumpWall(tester);
    await _startSelecting(tester);

    await _pressBack(tester);

    expect(find.text('1 selected'), findsNothing);
    expect(find.byType(WallpaperTile), findsWidgets);
  });

  testWidgets('a batch favorite saves every ticked wallpaper', (
    WidgetTester tester,
  ) async {
    final FakeFavoritesRepository favorites = FakeFavoritesRepository();
    await _pumpWall(tester, favorites: favorites);
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await _settle(tester);

    expect(
      await favorites.isFavorite(
        const WallpaperRef(SourceId.wallhaven, 'e7jvjd'),
      ),
      isTrue,
    );
    expect(
      await favorites.isFavorite(
        const WallpaperRef(SourceId.wallhaven, '7j1mzo'),
      ),
      isTrue,
    );
    expect(find.text('2 added to favorites'), findsOneWidget);
    // The batch is over, so the shelf is a shelf again.
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('a batch favorite over a mixed selection favorites all of them', (
    WidgetTester tester,
  ) async {
    // The trap `_favoriteAll` exists to avoid. Routing this through
    // `ToggleFavorite` would *un*-favorite exactly the wallpapers the user
    // could see were already hearted, so a button reading "Add to favorites"
    // would quietly remove some of them.
    final FakeFavoritesRepository favorites = FakeFavoritesRepository(
      initial: <Wallpaper>[_wallpaper('e7jvjd')],
    );
    await _pumpWall(tester, favorites: favorites);
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await _settle(tester);

    expect(
      await favorites.isFavorite(
        const WallpaperRef(SourceId.wallhaven, 'e7jvjd'),
      ),
      isTrue,
    );
    expect(
      await favorites.isFavorite(
        const WallpaperRef(SourceId.wallhaven, '7j1mzo'),
      ),
      isTrue,
    );
  });

  testWidgets('a batch queues rather than downloading inline', (
    WidgetTester tester,
  ) async {
    // The batch used to await one multi-megabyte original after another inside
    // this callback, so a hundred wallpapers took a hundred sequential
    // downloads and closing the app lost every one that had not landed. It now
    // says "queued", which is the honest word: nothing is on the device yet.
    final FakeDownloadQueue queue = FakeDownloadQueue();
    await _pumpWall(tester, queue: queue);
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);
    // Every unpinned batch asks where it lands now, safe or not.
    expect(find.text('Download 2 wallpapers to'), findsOneWidget);
    await _chooseGallery(tester);

    expect(find.text('Queued 2 wallpapers'), findsOneWidget);
    // And the selection is over, the same as every other finished batch.
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('re-queuing a wallpaper already waiting counts it once', (
    WidgetTester tester,
  ) async {
    // "Queued 2" over a queue that grew by one is the same aggregate lie the
    // old "Downloaded N" tally told. The entry already waiting is a *failed*
    // one, which is both the realistic case and the only one that survives the
    // drain the app starts the moment it launches.
    final FakeDownloadQueue queue = FakeDownloadQueue(
      initial: <QueuedDownload>[
        QueuedDownload(
          wallpaper: _wallpaper('e7jvjd'),
          queuedAt: DateTime.utc(2026, 7, 26),
          state: DownloadQueueState.failed,
          attempts: 1,
          failure: ImageStoreProblem.source,
        ),
      ],
    );
    await _pumpWall(tester, queue: queue);
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);
    await _chooseGallery(tester);

    expect(
      find.text('Queued 1 of 2 — the rest were already waiting'),
      findsOneWidget,
    );
    // And re-queuing did not reset the failed entry to a fresh pending one:
    // an enqueue is idempotent, not a retry.
    final QueuedDownload waiting = (await queue.entries()).single;
    expect(waiting.ref.id, 'e7jvjd');
    expect(waiting.state, DownloadQueueState.failed);
  });

  testWidgets('an unreachable folder is reported per entry, not per batch', (
    WidgetTester tester,
  ) async {
    // This used to abandon the whole batch with one toast. The queue is a
    // better place for it: each entry keeps its own reason and its own Retry,
    // so reconnecting the card recovers them instead of costing the selection.
    final FakeImageStore images = FakeImageStore(
      failure: const ImageStoreFailure(ImageStoreProblem.folderUnavailable),
    );
    final FakeDownloadQueue queue = FakeDownloadQueue();
    await _pumpWall(tester, images: images, queue: queue);
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);
    await _chooseGallery(tester);

    expect(find.text('Queued 2 wallpapers'), findsOneWidget);
    final List<QueuedDownload> left = await queue.entries();
    expect(left, hasLength(2));
    expect(
      left.every(
        (QueuedDownload e) => e.failure == ImageStoreProblem.folderUnavailable,
      ),
      isTrue,
    );
  });

  // K1 — a not-safe wallpaper in the batch is exactly what the single-download
  // chooser now guards for, so the batch owes the same question before landing.
  testWidgets('a not-safe batch asks where it lands', (
    WidgetTester tester,
  ) async {
    await _pumpWall(
      tester,
      wallpapers: <Wallpaper>[
        _wallpaper('e7jvjd', purity: Purity.sketchy),
        _wallpaper('7j1mzo'),
      ],
    );
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);

    // The intersection: one sketchy wallpaper keeps the gallery on offer, but
    // the chooser is up rather than the download running silently. The heading
    // counts the selection, so the tap does not read as one download.
    expect(find.text('Download 2 wallpapers to'), findsOneWidget);
    expect(find.text('Private library'), findsOneWidget);
  });

  // K2 was "a pin sends the batch straight through, no chooser". That is no
  // longer true, and deliberately so: a pin set weeks ago on a single wallpaper
  // became an invisible standing order over every later selection, which is
  // exactly how it presented on the device.
  testWidgets('a pin does not silence a batch; it pre-fills the chooser', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = FakeDownloadQueue();
    await _pumpWall(
      tester,
      queue: queue,
      settings: FakeSettingsRepository(
        pinnedDownloadTier: StorageTier.appPrivate,
      ),
      wallpapers: <Wallpaper>[
        _wallpaper('e7jvjd', purity: Purity.sketchy),
        _wallpaper('7j1mzo'),
      ],
    );
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);

    // The chooser is up, and it names the pin instead of acting silently.
    expect(find.text('Download 2 wallpapers to'), findsOneWidget);
    expect(
      find.text('Sending every download to Private library.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Private library'));
    await _settle(tester);

    expect(find.text('Queued 2 wallpapers'), findsOneWidget);
  });

  testWidgets('Stop clears the pin from the batch chooser', (
    WidgetTester tester,
  ) async {
    // The only place a batch user could reach the pin at all. It used to answer
    // "dismissed" without clearing anything, so the button did nothing.
    final FakeSettingsRepository settings = FakeSettingsRepository(
      pinnedDownloadTier: StorageTier.appPrivate,
    );
    final FakeDownloadQueue queue = FakeDownloadQueue();
    await _pumpWall(tester, queue: queue, settings: settings);
    await _startSelecting(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);
    await tester.tap(find.text('Stop'));
    await _settle(tester);

    expect(settings.pinnedTierSaved, isNull);
    expect(await queue.entries(), isEmpty);
  });

  testWidgets('a wholly safe batch is asked where it lands too', (
    WidgetTester tester,
  ) async {
    // It used to route silently, on the grounds that the chooser existed for
    // the destination a not-safe download must not enter unasked — which left
    // "put these two in my files folder" with no way to say it.
    await _pumpWall(tester);
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);

    expect(find.text('Download 2 wallpapers to'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Private library'), findsOneWidget);
  });

  testWidgets('dismissing the chooser queues nothing and keeps the ticks', (
    WidgetTester tester,
  ) async {
    final FakeDownloadQueue queue = FakeDownloadQueue();
    await _pumpWall(tester, queue: queue);
    await _startSelecting(tester);
    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);

    await _pressBack(tester);

    expect(await queue.entries(), isEmpty);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('closing the bar drops the selection without acting', (
    WidgetTester tester,
  ) async {
    final FakeFavoritesRepository favorites = FakeFavoritesRepository();
    await _pumpWall(tester, favorites: favorites);
    await _startSelecting(tester);

    await tester.tap(find.byIcon(Icons.close));
    await _settle(tester);

    expect(find.text('1 selected'), findsNothing);
    expect(favorites.saveCount, 0);
  });
}

Future<void> _longPressTile(WidgetTester tester, int index) async {
  await tester.longPress(find.byType(WallpaperTile).at(index));
  await _settle(tester);
}

/// Enters selection mode on the first tile, the way a user does.
Future<void> _startSelecting(WidgetTester tester) async {
  await _longPressTile(tester, 0);
  await tester.tap(find.text('Select wallpapers'));
  await _settle(tester);
}

Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

Future<void> _pumpWall(
  WidgetTester tester, {
  FakeFavoritesRepository? favorites,
  FakeImageStore? images,
  FakeSettingsRepository? settings,
  FakeDownloadQueue? queue,
  List<Wallpaper>? wallpapers,
}) async {
  // A real phone's geometry, not the 800x600 default — see the quick-sheet
  // suite, where the short default let a tap aimed at the sheet's last row
  // land on the bottom navigation bar instead.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final FakeWallpaperSource source = FakeWallpaperSource(
    page: WallpaperPage(
      wallpapers:
          wallpapers ??
          <Wallpaper>[
            _wallpaper('e7jvjd'),
            _wallpaper('7j1mzo'),
            _wallpaper('k8lvqm'),
          ],
      currentPage: 1,
      lastPage: 1,
      hasMore: false,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenSourceProvider.overrideWithValue(source),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        settingsRepositoryProvider.overrideWithValue(
          settings ?? FakeSettingsRepository(),
        ),
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
        favoritesRepositoryProvider.overrideWithValue(
          favorites ?? FakeFavoritesRepository(),
        ),
        downloadHistoryProvider.overrideWithValue(FakeDownloadHistory()),
        imageStoreProvider.overrideWithValue(images ?? FakeImageStore()),
        downloadQueueProvider.overrideWithValue(queue ?? FakeDownloadQueue()),
      ],
      child: const TelaApp(),
    ),
  );
  await _settle(tester);
}

/// Answers the batch destination chooser with the gallery.
///
/// Every unpinned batch shows it now, so a download test that does not answer
/// it is a test that never downloads anything.
Future<void> _chooseGallery(WidgetTester tester) async {
  await tester.tap(find.text('Gallery'));
  await _settle(tester);
}

/// The full-resolution network image keeps a progress indicator alive in widget
/// tests, so `pumpAndSettle` can never reach quiescence here.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Wallpaper _wallpaper(String id, {Purity purity = Purity.sfw}) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/xx/wallhaven-$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/xx/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/xx/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/xx/$id.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
