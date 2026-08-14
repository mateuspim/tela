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
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/featured_wallpaper.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// L4 — Browse's featured band: the listing's own first wallpaper, given the
/// width of the wall.
void main() {
  testWidgets('gives the listing its first wallpaper', (
    WidgetTester tester,
  ) async {
    await _pumpGrid(tester, _sourceOf(6));
    await _settle(tester);

    expect(find.byType(FeaturedWallpaper), findsOneWidget);
    expect(
      tester
          .widget<FeaturedWallpaper>(find.byType(FeaturedWallpaper))
          .wallpaper
          .id,
      'w0',
    );
  });

  testWidgets('draws no wallpaper twice', (WidgetTester tester) async {
    // The band takes the first item and the wall continues from the second.
    // Six wallpapers means six tiles in total, one of them inside the band —
    // seven would mean the featured one is also sitting in the grid.
    await _pumpGrid(tester, _sourceOf(6));
    await _settle(tester);

    expect(find.byType(WallpaperTile), findsNWidgets(6));
  });

  testWidgets('keeps the featured wallpaper first in reading order', (
    WidgetTester tester,
  ) async {
    // The layout law the whole wall rests on: reading order is list order, so
    // the pager and the index-keyed Hero tags need no compensation. The band
    // is read first, so it must be the first tile in the tree — which is also
    // why introducing it changed no existing browse test.
    await _pumpGrid(tester, _sourceOf(6));
    await _settle(tester);

    final WallpaperTile first = tester.widget<WallpaperTile>(
      find.byType(WallpaperTile).first,
    );
    expect(first.wallpaper.id, 'w0');
  });

  testWidgets('gets out of the way of a search', (WidgetTester tester) async {
    // A search is a question, and a masthead between someone and their answer
    // is the whole objection to a front page.
    await _pumpGrid(
      tester,
      _sourceOf(6),
      query: const SearchQuery(term: 'sunset'),
    );
    await _settle(tester);

    expect(find.byType(FeaturedWallpaper), findsNothing);
    expect(find.byType(WallpaperTile), findsNWidgets(6));
  });

  testWidgets('is absent from an empty listing', (WidgetTester tester) async {
    await _pumpGrid(tester, _sourceOf(0));
    await _settle(tester);

    expect(find.byType(FeaturedWallpaper), findsNothing);
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

FakeWallpaperSource _sourceOf(int count) => FakeWallpaperSource(
  pagesByNumber: <int, WallpaperPage>{
    1: WallpaperPage(
      wallpapers: <Wallpaper>[
        for (int index = 0; index < count; index++) _wallpaper(index),
      ],
      currentPage: 1,
      hasMore: false,
    ),
  },
);

Wallpaper _wallpaper(int index) => Wallpaper(
  id: 'w$index',
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/w$index'),
  fullImageUrl: 'https://w.wallhaven.cc/full/w/wallhaven-w$index.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/w/w$index.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/w/w$index.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/w/w$index.jpg',
  resolution: const Resolution(1920, 1080),
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>['#660000'],
);

Future<void> _pumpGrid(
  WidgetTester tester,
  FakeWallpaperSource source, {
  SearchQuery query = const SearchQuery(),
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenSourceProvider.overrideWithValue(source),
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
        home: WallpaperGrid(query: query),
      ),
    ),
  );
}
