import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/gallery_paging_bridge.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_detail_args.dart';

import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

void main() {
  test(
    'appends only the new page tail, deduplicated, into the session',
    () async {
      final PagingController<int, Wallpaper> paging = _twoPageController();
      addTearDown(paging.dispose);
      paging.fetchNextPage();
      await _settle(paging);
      expect(paging.value.items, hasLength(3));

      final GallerySessionController<Wallpaper> session =
          GallerySessionController<Wallpaper>(
            identity: 'browse:test',
            items: paging.value.items!,
            initialIndex: 2,
            itemKey: (Wallpaper wallpaper) => wallpaper.id,
          );
      addTearDown(session.dispose);
      expect(session.canSelectNext, isFalse);

      await GalleryPagingBridge(paging).appendNextPageInto(session);

      // Page 2 overlaps on 'c'; order is kept and the duplicate dropped.
      expect(session.items.map((Wallpaper w) => w.id).toList(), <String>[
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
      expect(session.selectedIndex, 2, reason: 'the selection does not move');
      expect(session.selectedItem.id, 'c');
      expect(
        session.canSelectNext,
        isTrue,
        reason: 'Next opens as items arrive',
      );
    },
  );

  testWidgets('the appended page inherits the live query and shuffle seed', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = _paginatedApi();
    await _openLastTile(
      tester,
      api,
      (GallerySessionController<Wallpaper> _) {},
    );

    final List<SearchQuery> pageTwo = api.receivedQueries
        .where((SearchQuery query) => query.page == 2)
        .toList();
    expect(pageTwo, hasLength(1), reason: 'exactly one page-2 request');
    expect(pageTwo.single.sorting, Sorting.random);
    expect(pageTwo.single.seed, 'seed-1');
  });
}

/// A paging controller whose two pages overlap on 'c'.
PagingController<int, Wallpaper> _twoPageController() {
  return PagingController<int, Wallpaper>(
    getNextPageKey: (PagingState<int, Wallpaper> state) =>
        (state.keys?.length ?? 0) >= 2 ? null : (state.keys?.length ?? 0) + 1,
    fetchPage: (int key) async => key == 1
        ? <Wallpaper>[_wallpaper('a'), _wallpaper('b'), _wallpaper('c')]
        : <Wallpaper>[_wallpaper('c'), _wallpaper('d'), _wallpaper('e')],
  );
}

/// Yields until the controller finishes its in-flight fetch.
Future<void> _settle(PagingController<int, Wallpaper> paging) async {
  while (paging.value.isLoading) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A fake whose two pages overlap on 'c' and carry a `random` shuffle seed.
FakeWallhavenApi _paginatedApi() {
  return FakeWallhavenApi(
    pagesByNumber: <int, WallpaperPage>{
      1: WallpaperPage(
        wallpapers: <Wallpaper>[
          _wallpaper('a'),
          _wallpaper('b'),
          _wallpaper('c'),
        ],
        currentPage: 1,
        lastPage: 2,
        seed: 'seed-1',
      ),
      2: WallpaperPage(
        wallpapers: <Wallpaper>[
          _wallpaper('c'),
          _wallpaper('d'),
          _wallpaper('e'),
        ],
        currentPage: 2,
        lastPage: 2,
        seed: 'seed-1',
      ),
    },
  );
}

Future<void> _openLastTile(
  WidgetTester tester,
  FakeWallhavenApi api,
  ValueChanged<GallerySessionController<Wallpaper>> onDetail,
) async {
  final GoRouter router = _router(onDetail: onDetail);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(api),
        // The grid re-filters against the blocklist on mount; keep that off
        // real Drift so this paging test only exercises the paging bridge.
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
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

  await tester.tap(find.byType(WallpaperTile).at(2));
  await tester.pumpAndSettle();
}

GoRouter _router({
  required ValueChanged<GallerySessionController<Wallpaper>> onDetail,
}) {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const WallpaperGrid(query: SearchQuery(sorting: Sorting.random)),
      ),
      GoRoute(
        path: TelaRoutes.detailPath,
        name: TelaRoutes.detailName,
        builder: (_, GoRouterState state) {
          final GallerySessionController<Wallpaper> session =
              (state.extra! as WallpaperDetailArgs).session;
          onDetail(session);
          return Scaffold(body: Text(session.selectedItem.id));
        },
      ),
    ],
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
