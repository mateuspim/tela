import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_download_queue.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_applier.dart';
import '../fakes/fake_wallpaper_sharer.dart';
import '../fakes/fake_wallpaper_source.dart';

/// D1 — the wall's long-press quick actions: favorite, download or set a
/// wallpaper without the round trip through the detail screen that collecting
/// used to cost on every tile.
void main() {
  testWidgets('a long press offers every quick action', (
    WidgetTester tester,
  ) async {
    await _pumpWall(tester);

    await _longPressTile(tester);

    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Set wallpaper'), findsOneWidget);
    expect(find.text('Copy image'), findsOneWidget);
    // Offered on a wallpaper nobody has downloaded — the whole wall is
    // undownloaded by definition — because a beam fetches what it needs on the
    // way out. Withholding it here was the bug (owner, 2026-08-26).
    expect(find.text('Beam'), findsOneWidget);
    expect(find.text('Open details'), findsOneWidget);
    // The sheet names the wallpaper: a long press that landed on the wrong tile
    // of a dense wall should be obvious before anything has been done to it.
    expect(find.text('Wallpaper e7jvjd'), findsOneWidget);
  });

  testWidgets('the sheet scrolls rather than clipping a short viewport', (
    WidgetTester tester,
  ) async {
    // A phone in landscape. A modal sheet is capped at a fraction of the screen
    // height, and the rows do not fit that cap — the first cut overflowed by
    // 31px, which is an action the user can see but not reach. One more row
    // (the beam) only makes that cap bite sooner.
    await _pumpWall(tester, size: const Size(2400, 1080));

    await _longPressTile(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable).hitTestable(), findsWidgets);
    await tester.dragUntilVisible(
      find.text('Open details'),
      find.byType(SingleChildScrollView).last,
      const Offset(0, -50),
    );
    expect(find.text('Open details'), findsOneWidget);
  });

  testWidgets('a plain tap still opens the detail screen', (
    WidgetTester tester,
  ) async {
    // The gesture the quick sheet is bolted onto must not have eaten the one
    // the whole core loop runs through.
    await _pumpWall(tester);

    await tester.tap(find.byType(WallpaperTile).first);
    await _settle(tester);

    expect(find.byType(WallpaperDetailScreen), findsOneWidget);
  });

  testWidgets('favoriting from the sheet saves the wallpaper', (
    WidgetTester tester,
  ) async {
    final FakeFavoritesRepository favorites = FakeFavoritesRepository();
    await _pumpWall(tester, favorites: favorites);

    await _longPressTile(tester);
    await tester.tap(find.text('Add to favorites'));
    await _settle(tester);

    expect(
      await favorites.isFavorite(
        const WallpaperRef(SourceId.wallhaven, 'e7jvjd'),
      ),
      isTrue,
    );
    // And the tile says so straight away. The mark is the only feedback this
    // action gives — it shows no snackbar — so a stale wall would leave the
    // user unable to tell whether the press landed.
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('the sheet offers to remove one already favorited', (
    WidgetTester tester,
  ) async {
    // Reads the live state rather than assuming the tile is new, the same way
    // the detail screen's heart does.
    await _pumpWall(
      tester,
      favorites: FakeFavoritesRepository(
        initial: <Wallpaper>[_wallpaper()],
      ),
    );

    await _longPressTile(tester);

    expect(find.text('Remove from favorites'), findsOneWidget);
    expect(find.text('Add to favorites'), findsNothing);
  });

  testWidgets('downloading from the sheet stores and records the wallpaper', (
    WidgetTester tester,
  ) async {
    final FakeImageStore images = FakeImageStore();
    final FakeDownloadHistory history = FakeDownloadHistory();
    await _pumpWall(tester, images: images, history: history);

    await _longPressTile(tester);
    await tester.tap(find.text('Download'));
    await _settle(tester);

    expect(images.receivedId, 'e7jvjd');
    expect(history.recorded.single.wallpaper.id, 'e7jvjd');
    expect(find.text('Wallpaper downloaded.'), findsOneWidget);
    // `refreshDownloads` reaching the tile marks, without a relaunch.
    expect(find.byIcon(Icons.download_done), findsOneWidget);
  });

  testWidgets('a download files under the tag Browse is searching for', (
    WidgetTester tester,
  ) async {
    // The other side of `ListingOrigin`: Browse publishes its own query and
    // nothing hands it a name, because the query *is* the name. Downloading a
    // page of `cyberpunk` means these wallpapers are that, which is the free
    // candidate `searchTagIn` has always answered — this pins that it survived
    // the move off `browseQueryProvider`.
    final FakeImageStore images = FakeImageStore();
    await _pumpWall(tester, images: images, term: 'cyberpunk');

    await _longPressTile(tester);
    await tester.tap(find.text('Download'));
    await _settle(tester);

    expect(images.receivedTag, TagFolder('cyberpunk'));
  });

  testWidgets('a safe download skips the chooser and routes silently', (
    WidgetTester tester,
  ) async {
    final FakeImageStore images = FakeImageStore();
    await _pumpWall(tester, images: images);

    await _longPressTile(tester);
    await tester.tap(find.text('Download'));
    await _settle(tester);

    // No dialog stood between the tap and the file: a plain tap stays silent.
    expect(find.text('Download to'), findsNothing);
    expect(images.receivedId, 'e7jvjd');
  });

  // The grid's only download path is this row — there is no long press to reach
  // a destination as the detail screen has — so a not-safe wallpaper opens the
  // chooser here, which is the remedy the tint on the row promises.
  testWidgets('a not-safe download opens the chooser first', (
    WidgetTester tester,
  ) async {
    final FakeImageStore images = FakeImageStore();
    await _pumpWall(tester, images: images, purity: Purity.sketchy);

    await _longPressTile(tester);
    await tester.tap(find.text('Download'));
    await _settle(tester);

    expect(find.text('Download to'), findsOneWidget);

    await tester.tap(find.text('Private library'));
    await _settle(tester);

    expect(images.receivedId, 'e7jvjd');
    expect(images.receivedTier, StorageTier.appPrivate);
  });

  testWidgets('setting a wallpaper asks which surface before applying', (
    WidgetTester tester,
  ) async {
    // Not a shortcut past the Home/Lock/Both question — the quick sheet saves
    // the trip to the detail screen, not the choice the apply needs.
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    await _pumpWall(tester, applier: applier);

    await _longPressTile(tester);
    await tester.tap(find.text('Set wallpaper'));
    await _settle(tester);
    expect(applier.callCount, 0);
    expect(find.text('Set wallpaper on'), findsOneWidget);

    await tester.tap(find.text('Lock screen'));
    await _settle(tester);

    expect(applier.callCount, 1);
    expect(applier.receivedTarget, WallpaperTarget.lock);
    expect(find.text('Wallpaper set.'), findsOneWidget);
  });

  testWidgets('copying from the sheet puts the image on the clipboard', (
    WidgetTester tester,
  ) async {
    // The wall's own route to a copy: no detail screen, no share sheet, no
    // holding the preview — the same long press everything else here uses.
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    await _pumpWall(tester, sharer: sharer);

    await _longPressTile(tester);
    await tester.tap(find.text('Copy image'));
    await _settle(tester);

    expect(sharer.copiedImages, hasLength(1));
    expect(
      sharer.copiedImages.single.source,
      Uri.parse('https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg'),
    );
  });

  testWidgets('an explicit wallpaper is offered the copy row too', (
    WidgetTester tester,
  ) async {
    // The row carries no purity condition of its own (`shareOptionsFor`), so
    // the sheet is the same six rows whatever the tile holds.
    final FakeWallpaperSharer sharer = FakeWallpaperSharer();
    await _pumpWall(tester, purity: Purity.nsfw, sharer: sharer);

    await _longPressTile(tester);
    await tester.tap(find.text('Copy image'));
    await _settle(tester);

    expect(sharer.copiedImages.single.sensitive, isTrue);
  });

  testWidgets('"Open details" opens the screen the tap would have', (
    WidgetTester tester,
  ) async {
    await _pumpWall(tester);

    await _longPressTile(tester);
    await tester.tap(find.text('Open details'));
    await _settle(tester);

    expect(find.byType(WallpaperDetailScreen), findsOneWidget);
  });
}

Future<void> _longPressTile(WidgetTester tester) async {
  await tester.longPress(find.byType(WallpaperTile).first);
  await _settle(tester);
}

Future<void> _pumpWall(
  WidgetTester tester, {
  FakeFavoritesRepository? favorites,
  FakeDownloadHistory? history,
  FakeImageStore? images,
  FakeWallpaperApplier? applier,
  FakeSettingsRepository? settings,
  FakeWallpaperSharer? sharer,
  Purity purity = Purity.sfw,
  Size size = const Size(1080, 2400),
  String term = '',
}) async {
  // A real phone's geometry, not the 800x600 default. It is load-bearing: a
  // modal sheet is capped at a fraction of the screen, and on the short default
  // the last row sits below that cap — where a tap aimed at it lands on the
  // bottom navigation bar instead and quietly switches tabs.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final FakeWallpaperSource source = FakeWallpaperSource(
    page: WallpaperPage(
      wallpapers: <Wallpaper>[_wallpaper(purity: purity)],
      hasMore: false,
      currentPage: 1,
      lastPage: 1,
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
        downloadHistoryProvider.overrideWithValue(
          history ?? FakeDownloadHistory(),
        ),
        imageStoreProvider.overrideWithValue(images ?? FakeImageStore()),
        downloadQueueProvider.overrideWithValue(FakeDownloadQueue()),
        wallpaperApplierProvider.overrideWithValue(
          applier ?? FakeWallpaperApplier(),
        ),
        // The Copy image row would otherwise reach the real method channel.
        wallpaperSharerProvider.overrideWithValue(
          sharer ?? FakeWallpaperSharer(),
        ),
      ],
      child: const TelaApp(),
    ),
  );
  await _settle(tester);
  if (term.isEmpty) return;
  // Typed rather than injected: the search field is what writes this provider
  // in the app, and a test that set it directly would not prove the wall is
  // publishing what the user actually searched.
  await tester.enterText(find.byType(TextField).first, term);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await _settle(tester);
}

/// The full-resolution network image keeps a progress indicator alive in widget
/// tests, so `pumpAndSettle` can never reach quiescence here.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Wallpaper _wallpaper({Purity purity = Purity.sfw}) => Wallpaper(
  id: 'e7jvjd',
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
