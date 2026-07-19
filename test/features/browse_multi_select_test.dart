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
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

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

    expect(await favorites.isFavorite('e7jvjd'), isTrue);
    expect(await favorites.isFavorite('7j1mzo'), isTrue);
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

    expect(await favorites.isFavorite('e7jvjd'), isTrue);
    expect(await favorites.isFavorite('7j1mzo'), isTrue);
  });

  testWidgets('a batch download reports the ones that failed', (
    WidgetTester tester,
  ) async {
    // "Downloaded 1 of 2" and "Downloaded 2" are different outcomes, and a
    // snackbar that rounds the first up to the second is a lie about what is
    // actually on the device.
    final FakeImageStore images = FakeImageStore(
      failingIds: const <String>{'7j1mzo'},
    );
    await _pumpWall(tester, images: images);
    await _startSelecting(tester);
    await tester.tap(find.byType(WallpaperTile).at(1));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await _settle(tester);

    expect(find.text('Downloaded 1 of 2 — 1 failed'), findsOneWidget);
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
}) async {
  // A real phone's geometry, not the 800x600 default — see the quick-sheet
  // suite, where the short default let a tap aimed at the sheet's last row
  // land on the bottom navigation bar instead.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final FakeWallhavenApi api = FakeWallhavenApi(
    page: WallpaperPage(
      wallpapers: <Wallpaper>[
        _wallpaper('e7jvjd'),
        _wallpaper('7j1mzo'),
        _wallpaper('k8lvqm'),
      ],
      currentPage: 1,
      lastPage: 1,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(api),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
        favoritesRepositoryProvider.overrideWithValue(
          favorites ?? FakeFavoritesRepository(),
        ),
        downloadHistoryProvider.overrideWithValue(FakeDownloadHistory()),
        imageStoreProvider.overrideWithValue(images ?? FakeImageStore()),
      ],
      child: const TelaApp(),
    ),
  );
  await _settle(tester);
}

/// The full-resolution network image keeps a progress indicator alive in widget
/// tests, so `pumpAndSettle` can never reach quiescence here.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  fullImageUrl: 'https://w.wallhaven.cc/full/xx/wallhaven-$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/xx/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/xx/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/xx/$id.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
