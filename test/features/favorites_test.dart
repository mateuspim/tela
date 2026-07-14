import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';
import 'package:tela/features/favorites/favorites_screen.dart';

import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_wallhaven_api.dart';

void main() {
  group('FavoritesScreen', () {
    testWidgets('invites the first favorite when nothing is saved', (
      WidgetTester tester,
    ) async {
      await _pumpFavorites(tester, FakeFavoritesRepository());

      expect(find.textContaining('Nothing saved yet'), findsOneWidget);
      expect(find.byType(WallpaperTile), findsNothing);
    });

    testWidgets('renders a tile per saved wallpaper, newest first', (
      WidgetTester tester,
    ) async {
      await _pumpFavorites(
        tester,
        FakeFavoritesRepository(
          initial: <Wallpaper>[_wallpaper('older'), _wallpaper('newer')],
        ),
      );

      expect(find.byType(WallpaperTile), findsNWidgets(2));
      final Iterable<WallpaperTile> tiles = tester.widgetList<WallpaperTile>(
        find.byType(WallpaperTile),
      );
      expect(
        tiles.map((WallpaperTile tile) => tile.wallpaper.id),
        <String>['newer', 'older'],
      );
    });

    testWidgets('renders saved wallpapers with Wallhaven unreachable', (
      WidgetTester tester,
    ) async {
      // The point of storing whole rows: favorites are the offline shelf, so
      // this screen must never need the API to draw itself.
      await _pumpFavorites(
        tester,
        FakeFavoritesRepository(initial: <Wallpaper>[_wallpaper('e7jvjd')]),
      );

      expect(find.byType(WallpaperTile), findsOneWidget);
    });
  });

  group('FavoriteButton', () {
    testWidgets('starts empty and saves the wallpaper when tapped', (
      WidgetTester tester,
    ) async {
      final FakeFavoritesRepository favorites = FakeFavoritesRepository();
      await _pumpDetail(tester, favorites);

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(await favorites.isFavorite('e7jvjd'), isTrue);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('starts filled for an already-saved wallpaper', (
      WidgetTester tester,
    ) async {
      await _pumpDetail(
        tester,
        FakeFavoritesRepository(initial: <Wallpaper>[_wallpaper('e7jvjd')]),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('tapping a saved wallpaper forgets it', (
      WidgetTester tester,
    ) async {
      final FakeFavoritesRepository favorites = FakeFavoritesRepository(
        initial: <Wallpaper>[_wallpaper('e7jvjd')],
      );
      await _pumpDetail(tester, favorites);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(await favorites.isFavorite('e7jvjd'), isFalse);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });
  });
}

/// Boots the real FavoritesScreen over [favorites], with no API bound at all.
Future<void> _pumpFavorites(
  WidgetTester tester,
  FakeFavoritesRepository favorites,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        favoritesRepositoryProvider.overrideWithValue(favorites),
      ],
      child: _app(const FavoritesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Boots the real detail screen, which carries the heart in its app bar.
Future<void> _pumpDetail(
  WidgetTester tester,
  FakeFavoritesRepository favorites,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        favoritesRepositoryProvider.overrideWithValue(favorites),
        wallhavenApiProvider.overrideWithValue(
          FakeWallhavenApi(details: _details()),
        ),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
      ],
      child: _app(WallpaperDetailScreen(wallpaper: _wallpaper('e7jvjd'))),
    ),
  );
  await tester.pump();
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

WallpaperDetails _details() => WallpaperDetails(
  wallpaper: _wallpaper('e7jvjd'),
  fileType: 'image/jpeg',
  ratio: '0.45',
  views: 10,
  favorites: 2,
  tags: const <WallpaperTag>[WallpaperTag(id: 1, name: 'sunset')],
  uploader: const WallpaperUploader(
    username: 'tela-fixture',
    group: '',
    avatarUrl: '',
  ),
  source: '',
);

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
