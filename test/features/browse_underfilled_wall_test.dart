import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tile_density_scope.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/tile_density.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

/// A shelf too short to scroll must still reach its second page.
///
/// The device found this one (2026-07-19, SM-X730). The next-page trigger only
/// ever runs off a `ScrollNotification`, and a wall shorter than its viewport
/// emits none — nothing scrolls — so the listing stopped at page one under a
/// large dead void. It became reachable when the tile-density setting landed:
/// at *Small* on a 2560x1600 tablet, Wallhaven's 24-item page leaves rows to
/// spare. Swiping at the void was the only way out, because a drag emits a
/// notification even where there is nothing to scroll.
/// The 16x9 shape Browse's default listing is stocked with.
const Resolution _wide = Resolution(1920, 1080);

void main() {
  testWidgets('a first page that does not fill the viewport fetches the next', (
    WidgetTester tester,
  ) async {
    // Two tiles cannot fill a tall viewport; page 2 says the listing goes on.
    final FakeWallhavenApi api = FakeWallhavenApi(
      pagesByNumber: <int, WallpaperPage>{
        1: _page(count: 2, currentPage: 1, lastPage: 3),
        2: _page(count: 2, currentPage: 2, lastPage: 3),
      },
    );

    await _pumpGrid(tester, api);
    await tester.pump(const Duration(milliseconds: 300));
    // A second frame: the top-up is scheduled post-frame, and the page it asks
    // for needs a frame of its own to arrive and lay out.
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      api.receivedQueries.map((SearchQuery q) => q.page),
      containsAllInOrder(<int>[1, 2]),
      reason:
          'an under-filled wall must ask for the next page itself, with '
          'no scroll to prompt it',
    );
    expect(
      find.byType(WallpaperTile),
      findsNWidgets(4),
      reason: 'and both pages must reach the wall',
    );
  });

  testWidgets('a wall that already overflows does not fetch ahead', (
    WidgetTester tester,
  ) async {
    // The guard that keeps the top-up from turning into an eager prefetch: with
    // a scroll extent to spare, paging stays the scroll trigger's job. Without
    // this the fix would pull pages the user never scrolled to.
    final FakeWallhavenApi api = FakeWallhavenApi(
      pagesByNumber: <int, WallpaperPage>{
        1: _page(count: 40, currentPage: 1, lastPage: 3),
        2: _page(count: 40, currentPage: 2, lastPage: 3),
      },
    );

    await _pumpGrid(tester, api);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      api.receivedQueries.map((SearchQuery q) => q.page),
      everyElement(1),
      reason: 'a wall taller than its viewport pages on scroll, not on build',
    );
  });

  testWidgets('the top-up stops at the end of the listing', (
    WidgetTester tester,
  ) async {
    // `hasNextPage` is the other guard. A short *final* page is the steady
    // state of every narrow search, and a top-up that ignored the end of the
    // listing would spin on it forever.
    final FakeWallhavenApi api = FakeWallhavenApi(
      pagesByNumber: <int, WallpaperPage>{
        1: _page(count: 2, currentPage: 1, lastPage: 1),
      },
    );

    await _pumpGrid(tester, api);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      api.receivedQueries.length,
      1,
      reason: 'the only page there is must be requested exactly once',
    );
  });
  testWidgets('shrinking the tiles tops up a wall that no longer overflows', (
    WidgetTester tester,
  ) async {
    // The transition the device actually hit, with the scroll top-up already
    // in place. A page that overflows at Medium leaves rows to spare at Small,
    // and the re-pack happens inside `JustifiedWallpaperGrid` — one layer below
    // the build that schedules the top-up. Without a density dependency up in
    // the grid, nothing re-registers the check and the wall sits half-empty
    // under a dead void until a swipe at nothing shakes a notification loose.
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.125;
    addTearDown(tester.view.reset);

    final FakeWallhavenApi api = FakeWallhavenApi(
      pagesByNumber: <int, WallpaperPage>{
        1: _page(count: 24, currentPage: 1, lastPage: 5, resolution: _wide),
        2: _page(count: 24, currentPage: 2, lastPage: 5, resolution: _wide),
        3: _page(count: 24, currentPage: 3, lastPage: 5, resolution: _wide),
      },
    );

    // The harness mounts at Medium, where this page overflows.
    await _pumpGrid(tester, api);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final int settled = api.receivedQueries.length;

    await _pumpGrid(tester, api, density: TileDensity.small);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      api.receivedQueries.length,
      greaterThan(settled),
      reason:
          'the smaller wall no longer fills its viewport, so it must ask '
          'for another page rather than wait for a scroll that cannot happen',
    );
  });
}

/// Mounts the grid on a viewport a two-tile page cannot fill.
Future<void> _pumpGrid(
  WidgetTester tester,
  FakeWallhavenApi api, {
  TileDensity density = TileDensity.medium,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(api),
        // Mounting the grid reads the standing blocklist. Left unbound, it
        // opens the real database.
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext context, Widget? child) =>
            TileDensityScope(density: density, child: child!),
        home: const WallpaperGrid(query: SearchQuery()),
      ),
    ),
  );
}

/// A page of [count] distinct wallpapers, in a listing [lastPage] pages long.
///
/// [resolution] is load-bearing in the density test: the packing fits a row to
/// the shelf's width, so *portrait* tiles come out tall enough to overflow the
/// viewport at every density, and only a landscape wall — what Browse's default
/// 16x9 listing actually returns — is short enough to strand rows at Small.
WallpaperPage _page({
  required int count,
  required int currentPage,
  required int lastPage,
  Resolution resolution = const Resolution(1080, 2400),
}) {
  return WallpaperPage(
    wallpapers: <Wallpaper>[
      for (int i = 0; i < count; i++)
        _wallpaper('p${currentPage}w$i', resolution),
    ],
    currentPage: currentPage,
    lastPage: lastPage,
  );
}

Wallpaper _wallpaper(
  String id, [
  Resolution resolution = const Resolution(1080, 2400),
]) => Wallpaper(
  id: id,
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: resolution,
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
