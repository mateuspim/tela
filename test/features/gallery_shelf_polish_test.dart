import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_route_transitions.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/tile_density.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/favorites/favorites_grid.dart';

import '../fakes/fake_favorites_repository.dart';

void main() {
  group('shared grid geometry', () {
    final List<(String, Size, int)> surfaces = <(String, Size, int)>[
      ('390x844 compact portrait', const Size(390, 844), 2),
      ('844x390 compact landscape', const Size(844, 390), 4),
      ('1280x800 expanded landscape', const Size(1280, 800), 6),
    ];

    for (final (String name, Size size, int columns) in surfaces) {
      testWidgets('$name caps rows at $columns tiles with a 12dp inset', (
        WidgetTester tester,
      ) async {
        late int actualColumns;
        late EdgeInsets actualPadding;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size),
            child: Builder(
              builder: (BuildContext context) {
                actualColumns = wallpaperRowTileCap(
                  size.width,
                  TileDensity.medium,
                );
                actualPadding = wallpaperGridPadding(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(actualColumns, columns);
        expect(actualPadding, const EdgeInsets.all(wallpaperGridSpacing));
      });
    }

    testWidgets('edge padding clears the system safe areas', (
      WidgetTester tester,
    ) async {
      late EdgeInsets padding;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(844, 390),
            padding: EdgeInsets.only(left: 24, right: 8, bottom: 48),
          ),
          child: Builder(
            builder: (BuildContext context) {
              padding = wallpaperGridPadding(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // 12dp rhythm plus the un-consumed inset on each edge; the top is the
      // app bar's to own, so it stays at the bare rhythm.
      expect(padding, const EdgeInsets.fromLTRB(36, 12, 20, 60));
    });

    for (final (String name, Size size, int _) in surfaces) {
      testWidgets('a full shelf packs at $name without overflowing', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpFavorites(
          tester,
          FakeFavoritesRepository(
            initial: List<Wallpaper>.generate(20, (int i) => _wallpaper('w$i')),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(WallpaperTile), findsWidgets);
      });
    }
  });

  group('shelf-scoped Hero tags', () {
    testWidgets('the same id on two shelves renders two distinct Hero tags', (
      WidgetTester tester,
    ) async {
      // Browse and Favorites are both alive in the shell's IndexedStack, so a
      // wallpaper kept in Favorites and shown in Browse must not share a tag.
      await tester.pumpWidget(
        _app(
          Column(
            children: <Widget>[
              Expanded(
                child: WallpaperTile(
                  wallpaper: _wallpaper('shared'),
                  heroTag: shelfHeroTag('browse?page=1', 'shared', 0),
                ),
              ),
              Expanded(
                child: WallpaperTile(
                  wallpaper: _wallpaper('shared'),
                  heroTag: shelfHeroTag('favorites', 'shared', 0),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final Iterable<Object> tags = tester
          .widgetList<Hero>(find.byType(Hero))
          .map((Hero hero) => hero.tag);
      expect(tags, hasLength(2));
      expect(tags.toSet(), hasLength(2), reason: 'tags must not collide');
    });

    testWidgets('a scoped tile flies into its viewer without a collision', (
      WidgetTester tester,
    ) async {
      final GoRouter router = _router(
        home: Column(
          children: <Widget>[
            _linkTile('browse?page=1', 'shared'),
            _linkTile('favorites', 'shared'),
          ],
        ),
      );
      addTearDown(router.dispose);
      await _pumpRouter(tester, router);

      await tester.tap(find.byKey(const Key('tap-favorites')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('viewer-hero')), findsOneWidget);
    });
  });

  group('transitions', () {
    testWidgets('reduce motion collapses the shelf transition to instant', (
      WidgetTester tester,
    ) async {
      final GoRouter router = _router(home: _linkTile('favorites', 'one'));
      addTearDown(router.dispose);
      await _pumpRouter(tester, router, disableAnimations: true);

      await tester.tap(find.byKey(const Key('tap-favorites')));
      await tester.pump();

      // A zero-duration route also collapses the Hero flight, so the viewer is
      // fully present after a single frame with nothing still animating.
      expect(find.byKey(const Key('viewer-hero')), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('tile edge', () {
    testWidgets('a tile frames its thumbnail with a hairline border', (
      WidgetTester tester,
    ) async {
      // A pale wallpaper on a pale surface needs a containing edge, or it melts
      // into the gutter. Every tile draws one over the image.
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 200,
              child: WallpaperTile(wallpaper: _wallpaper('edge')),
            ),
          ),
        ),
      );
      await tester.pump();

      final Iterable<Container> framed = tester
          .widgetList<Container>(find.byType(Container))
          .where((Container box) => box.foregroundDecoration is BoxDecoration);
      expect(framed, isNotEmpty);
      final BoxDecoration edge =
          framed.first.foregroundDecoration! as BoxDecoration;
      expect(edge.border, isNotNull);
    });
  });

  group('decode budget', () {
    testWidgets('a tile decodes the thumbnail at a bounded display size', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 200,
              child: WallpaperTile(wallpaper: _wallpaper('budget')),
            ),
          ),
        ),
      );
      await tester.pump();

      final CachedNetworkImage image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      // The original thumbnail, never the multi-megapixel full image, and
      // capped so a shelf never decodes a gallery of 6K originals.
      expect(image.imageUrl, contains('/orig/'));
      expect(image.memCacheWidth, isNotNull);
      expect(image.memCacheWidth, lessThanOrEqualTo(600));
    });
  });

  group('scroll restoration', () {
    testWidgets('returning from a viewer restores the shelf scroll offset', (
      WidgetTester tester,
    ) async {
      final GoRouter router = _router(
        home: const Scaffold(body: FavoritesGrid()),
        includeDetail: true,
      );
      addTearDown(router.dispose);
      await _pumpRouter(
        tester,
        router,
        overrides: <Override>[
          favoritesRepositoryProvider.overrideWithValue(
            FakeFavoritesRepository(
              initial: List<Wallpaper>.generate(
                40,
                (int i) => _wallpaper('item-$i'),
              ),
            ),
          ),
        ],
      );

      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      await tester.drag(find.byType(Scrollable), const Offset(0, -600));
      await tester.pumpAndSettle();
      final double before = scrollable.position.pixels;
      expect(before, greaterThan(0));

      await tester.tap(find.byType(WallpaperTile).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-stub')), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(FavoritesGrid), findsOneWidget);
      expect(scrollable.position.pixels, before);
    });
  });
}

/// A tile that pushes a fade-transitioned viewer carrying the matching Hero.
Widget _linkTile(String identity, String id) {
  return Builder(
    builder: (BuildContext context) {
      return SizedBox(
        height: 200,
        child: GestureDetector(
          key: Key('tap-$identity'),
          onTap: () => context.pushNamed(
            TelaRoutes.downloadViewerName,
            extra: shelfHeroTag(identity, id, 0),
          ),
          child: WallpaperTile(
            wallpaper: _wallpaper(id),
            heroTag: shelfHeroTag(identity, id, 0),
          ),
        ),
      );
    },
  );
}

GoRouter _router({
  required Widget home,
  bool includeDetail = false,
}) {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: TelaRoutes.downloadViewerPath,
        name: TelaRoutes.downloadViewerName,
        pageBuilder: (BuildContext context, GoRouterState state) =>
            fadeGalleryPage<void>(
              context: context,
              child: Scaffold(
                body: Center(
                  child: Hero(
                    tag: state.extra!,
                    child: const SizedBox(
                      key: Key('viewer-hero'),
                      width: 100,
                      height: 100,
                    ),
                  ),
                ),
              ),
            ),
      ),
      if (includeDetail)
        GoRoute(
          path: TelaRoutes.detailPath,
          name: TelaRoutes.detailName,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              fadeGalleryPage<void>(
                context: context,
                child: const Scaffold(
                  body: Center(child: Text('detail', key: Key('detail-stub'))),
                ),
              ),
        ),
    ],
  );
}

Future<void> _pumpRouter(
  WidgetTester tester,
  GoRouter router, {
  bool disableAnimations = false,
  List<Override> overrides = const <Override>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
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

Future<void> _pumpFavorites(
  WidgetTester tester,
  FakeFavoritesRepository favorites,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        favoritesRepositoryProvider.overrideWithValue(favorites),
      ],
      child: _app(const Scaffold(body: FavoritesGrid())),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _app(Widget home) {
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
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
