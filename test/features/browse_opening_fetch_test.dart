import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/browse_screen.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

/// The startup hang, pinned at the two altitudes it lives at.
///
/// The device found this one: a release build cold-launched to a spinner that
/// never resolved, while tapping any sorting tab loaded instantly — a tab tap
/// mounts a *different* [WallpaperGrid], with a paging controller that has not
/// been poisoned yet, which is why the workaround looked like magic.
void main() {
  testWidgets('a query change lands even before the opening fetch has drawn', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi(
      page: _page(count: 2, currentPage: 1, lastPage: 1),
    );
    final FakeTagBlocklistRepository blocklist = FakeTagBlocklistRepository();

    // One frame only. The grid is mounted and its opening fetch is away — but
    // no frame has drawn that fetch's `isLoading` state yet, so as far as the
    // paging layout is concerned the state is still the pristine one it was
    // built with.
    await _pumpGrid(tester, api, blocklist, const SearchQuery());

    // Now the query changes underneath it, which is what browse defaults
    // resolving asynchronously at startup does. `refresh()` clears the paging
    // controller's in-flight guard and resets the state to pristine — and
    // pristine is exactly what the layout already has, so nothing observes a
    // change and nothing re-fetches. The opening fetch's own result is
    // discarded as stale on arrival. Nobody is left to ask again.
    await _pumpGrid(
      tester,
      api,
      blocklist,
      const SearchQuery(categories: CategoryFilter({Category.anime})),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(WallpaperTile),
      findsNWidgets(2),
      reason: 'the grid must reach content, not spin forever',
    );
    expect(
      api.receivedQueries.last.categories,
      const CategoryFilter({Category.anime}),
      reason: 'and it must be the new query that was fetched',
    );
  });

  testWidgets('a fetch the grid abandoned cannot end the listing that replaced '
      'it', (WidgetTester tester) async {
    // The abandoned listing is a single complete page; the one that replaces it
    // has five. Crucially the abandoned one answers *last* — a request already
    // in flight when the query changed, dawdling past the fetch that superseded
    // it. `PagingController` drops its items, but nothing was stopping it from
    // writing its own `hasMore: false` over the new listing's page.
    final FakeWallhavenApi api = FakeWallhavenApi(
      pageFor: (SearchQuery query) => _isAnime(query)
          // Enough to fill the viewport, so the grid asks for page 2 only when
          // this test does — and never to fill a gap under the last row.
          ? _page(count: 24, currentPage: query.page, lastPage: 5)
          : _page(count: 2, currentPage: 1, lastPage: 1),
      searchDelay: (SearchQuery query) =>
          _isAnime(query) ? Duration.zero : const Duration(milliseconds: 500),
    );
    final FakeTagBlocklistRepository blocklist = FakeTagBlocklistRepository();

    await _pumpGrid(tester, api, blocklist, const SearchQuery());
    await _pumpGrid(tester, api, blocklist, _anime);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(WallpaperTile), findsWidgets);

    // The abandoned request finally answers, onto the listing that replaced it.
    await tester.pump(const Duration(milliseconds: 500));

    // Ask for the next page the way scrolling to the end does. A grid holding a
    // stale `hasMore: false` answers "there is no next page" — and once that is
    // recorded it is never revisited, so the listing simply stops at page one.
    _paging(tester).fetchNextPage();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      _paging(tester).value.hasNextPage,
      isTrue,
      reason: 'the new listing has five pages, and must know it',
    );
  });

  testWidgets('browse loads when its defaults resolve into the opening fetch', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi(
      page: _page(count: 2, currentPage: 1, lastPage: 1),
    );
    // Defaults that differ from tela's own, so adopting them genuinely changes
    // the query — the startup rewrite the device hangs on. Defaults equal to
    // tela's own are why every other browse test passes over this: an unchanged
    // query never reaches `didUpdateWidget`.
    final FakeSettingsRepository settings = FakeSettingsRepository(
      source: BrowseDefaultsSource.device,
      deviceDefaults: const BrowseDefaults(
        categories: CategoryFilter({Category.anime}),
      ),
    );

    await _pumpBrowse(tester, api, settings);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The cold-launch symptom, at the altitude the owner saw it: wallpapers, or
    // a spinner that never goes away.
    expect(find.byType(WallpaperTile), findsNWidgets(2));
    expect(
      api.receivedQueries.last.categories,
      const CategoryFilter({Category.anime}),
    );
  });

  testWidgets('browse loads when the screen metrics land a frame late', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final FakeWallhavenApi api = FakeWallhavenApi(
      page: _page(count: 2, currentPage: 1, lastPage: 1),
    );

    await _pumpBrowse(tester, api, FakeSettingsRepository());

    // Android hands Flutter its real display metrics after the first frame is
    // already up, and browse folds the screen's size into every query it makes
    // — an *Automatic* resolution filter means "nothing smaller than this
    // screen", and only a widget can answer how big the screen is. So the
    // opening query is rewritten on the way past, on every cold launch, with no
    // account, no key and no saved filters needed to provoke it. This is the
    // trigger a wiped tablet still hangs on, and the reason a fixed test
    // viewport never saw the bug that the device found immediately.
    tester.view.physicalSize = const Size(1600, 2560);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(WallpaperTile), findsNWidgets(2));
    expect(
      (api.receivedQueries.last.resolution as AtLeastResolution).minimum,
      const Resolution(1600, 2560),
      reason: 'and it asks for images that fit the screen it actually has',
    );
  });
}

/// Boots the real browse screen with the network and the settings store faked.
///
/// Deliberately **one** frame, and no `pumpAndSettle`: the frame after the
/// first is where the startup query rewrite lands, and settling here would step
/// straight over the window under test.
Future<void> _pumpBrowse(
  WidgetTester tester,
  FakeWallhavenApi api,
  FakeSettingsRepository settings,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(api),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        settingsRepositoryProvider.overrideWithValue(settings),
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: BrowseScreen(),
      ),
    ),
  );
}

/// The query browse adopts once its defaults land — anything that is not
/// tela's own, so that adopting it genuinely rewrites the grid's query.
const SearchQuery _anime = SearchQuery(
  categories: CategoryFilter({Category.anime}),
);

bool _isAnime(SearchQuery query) => query.categories == _anime.categories;

/// The grid's paging controller: what drives its fetches and where the paging
/// state can be read back.
///
/// Read off the [PagingListener] the grid builds with. The wall itself is laid
/// out by hand now (justified rows, not a paged grid widget), so there is no
/// paged-view widget left to interrogate — the controller is the seam.
PagingController<int, Wallpaper> _paging(WidgetTester tester) {
  return tester
      .widget<PagingListener<int, Wallpaper>>(
        find.byType(PagingListener<int, Wallpaper>),
      )
      .controller;
}

/// Mounts the grid on [query], reusing [api] and [blocklist] so that pumping a
/// new query updates the existing grid rather than remounting it — the
/// difference between the bug and the tab tap that works around it.
Future<void> _pumpGrid(
  WidgetTester tester,
  FakeWallhavenApi api,
  FakeTagBlocklistRepository blocklist,
  SearchQuery query,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(api),
        // Mounting the grid reads the standing blocklist. Left unbound, it
        // opens the real database.
        tagBlocklistRepositoryProvider.overrideWithValue(blocklist),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WallpaperGrid(query: query),
      ),
    ),
  );
}

/// A page of [count] distinct wallpapers, [lastPage] pages into the listing.
///
/// [count] is load-bearing where it is large: a page that fills the viewport
/// stops [PagedMasonryGridView] from eagerly fetching the next one to fill the
/// gap, which is what lets a test say when a fetch happens.
WallpaperPage _page({
  required int count,
  required int currentPage,
  required int lastPage,
}) {
  return WallpaperPage(
    wallpapers: <Wallpaper>[
      for (int i = 0; i < count; i++) _wallpaper('p${currentPage}w$i'),
    ],
    currentPage: currentPage,
    lastPage: lastPage,
  );
}

Wallpaper _wallpaper(String id) => Wallpaper(
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
);
