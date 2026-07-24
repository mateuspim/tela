import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_detail_args.dart';
import 'package:tela/features/favorites/favorites_grid.dart';

import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

void main() {
  testWidgets('query shelf opens the exact tapped item with all loaded items', (
    WidgetTester tester,
  ) async {
    final List<Wallpaper> loaded = <Wallpaper>[
      _wallpaper('first'),
      _wallpaper('second'),
      _wallpaper('third'),
    ];
    GallerySessionController<Wallpaper>? captured;
    final GoRouter router = _router(
      home: const WallpaperGrid(query: SearchQuery()),
      onDetail: (GallerySessionController<Wallpaper> session) {
        captured = session;
      },
    );
    addTearDown(router.dispose);
    await _pump(
      tester,
      router,
      <Override>[
        wallhavenApiProvider.overrideWithValue(
          FakeWallhavenApi(
            page: WallpaperPage(
              wallpapers: loaded,
              hasMore: false,
              currentPage: 1,
              lastPage: 1,
            ),
          ),
        ),
        // The grid re-filters against the blocklist on mount; give it an
        // in-memory one so this shelf-launch test never reaches real Drift.
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
      ],
    );

    await tester.tap(find.byType(WallpaperTile).at(1));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.identity, startsWith('browse?'));
    expect(captured!.items, loaded);
    expect(captured!.selectedIndex, 1);
    expect(captured!.selectedItem.id, 'second');
    expect(
      captured!.canRequestMore,
      isTrue,
      reason: 'a Browse shelf can page for more',
    );
  });

  testWidgets('Favorites returns to the same scrolled shelf after Detail', (
    WidgetTester tester,
  ) async {
    final List<Wallpaper> inserted = List<Wallpaper>.generate(
      30,
      (int index) => _wallpaper('item-$index'),
    );
    GallerySessionController<Wallpaper>? captured;
    final GoRouter router = _router(
      home: const Scaffold(body: FavoritesGrid()),
      onDetail: (GallerySessionController<Wallpaper> session) {
        captured = session;
      },
    );
    addTearDown(router.dispose);
    await _pump(
      tester,
      router,
      <Override>[
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(initial: inserted),
        ),
      ],
    );

    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    await tester.drag(find.byType(Scrollable), const Offset(0, -700));
    await tester.pumpAndSettle();
    final double before = scrollable.position.pixels;
    final Element visibleElement = find
        .byType(WallpaperTile)
        .evaluate()
        .firstWhere((Element element) {
          final RenderBox box = element.renderObject! as RenderBox;
          final double y = box.localToGlobal(Offset.zero).dy;
          return y < 590 && y + box.size.height > 80;
        });
    final Finder visibleTile = find.byElementPredicate(
      (Element element) => identical(element, visibleElement),
    );
    final Wallpaper tapped = tester
        .widget<WallpaperTile>(visibleTile)
        .wallpaper;

    final RenderBox visibleBox = visibleElement.renderObject! as RenderBox;
    final Offset topLeft = visibleBox.localToGlobal(Offset.zero);
    final double visibleTop = topLeft.dy < 80 ? 80 : topLeft.dy;
    final double bottom = topLeft.dy + visibleBox.size.height;
    final double visibleBottom = bottom > 590 ? 590 : bottom;
    final double tapY = (visibleTop + visibleBottom) / 2;
    await tester.tapAt(Offset(topLeft.dx + visibleBox.size.width / 2, tapY));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.identity, 'favorites');
    expect(captured!.selectedItem, tapped);
    expect(captured!.items[captured!.selectedIndex], tapped);
    expect(captured!.items, inserted.reversed.toList());
    expect(
      captured!.canRequestMore,
      isFalse,
      reason: 'Favorites is a complete local snapshot and never pages',
    );

    router.pop();
    await tester.pumpAndSettle();

    expect(find.byType(FavoritesGrid), findsOneWidget);
    expect(scrollable.position.pixels, before);
  });
}

GoRouter _router({
  required Widget home,
  required ValueChanged<GallerySessionController<Wallpaper>> onDetail,
}) {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: TelaRoutes.detailPath,
        name: TelaRoutes.detailName,
        builder: (_, GoRouterState state) {
          // Faithful to the real router: a grid wraps the session with its
          // origin filters, while a curated shelf pushes the session bare.
          final Object extra = state.extra!;
          final GallerySessionController<Wallpaper> session =
              extra is WallpaperDetailArgs
              ? extra.session
              : extra as GallerySessionController<Wallpaper>;
          onDetail(session);
          return Scaffold(body: Text(session.selectedItem.id));
        },
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  GoRouter router,
  List<Override> overrides,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Wallpaper _wallpaper(String id) => Wallpaper(
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
);
