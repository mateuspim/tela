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

  testWidgets('says which listing it is the top of', (
    WidgetTester tester,
  ) async {
    // "Why is this one big?" deserves an answer, and the listing already gives
    // it — on Most favorited this *is* the most favorited wallpaper. Taken from
    // the same `sortingLabel` the tabs use, so the band cannot claim one thing
    // while the tab above it says another.
    await _pumpGrid(
      tester,
      _sourceOf(6),
      query: const SearchQuery(sorting: Sorting.favorites),
    );
    await _settle(tester);

    // Two of each: the caption is drawn as an outline with its fill over it,
    // so both lines exist twice by construction.
    expect(find.text('MOST FAVORITED'), findsNWidgets(2));
    expect(find.text('1920x1080'), findsNWidgets(2));
  });

  testWidgets('outlines the caption so it survives a pale wallpaper', (
    WidgetTester tester,
  ) async {
    // The wash below the caption is a fixed darkening; whether white type
    // survives depends on the wallpaper's own pixels behind those glyphs. Same
    // argument as `wallpaperTileEdge`, and the same reason C2's scrim was left
    // alone rather than raised.
    await _pumpGrid(tester, _sourceOf(6));
    await _settle(tester);

    final Iterable<Text> lines = tester.widgetList<Text>(
      find.text('1920x1080'),
    );
    expect(
      lines.where(
        (Text t) => t.style?.foreground?.style == PaintingStyle.stroke,
      ),
      hasLength(1),
      reason: 'exactly one layer is the outline',
    );
    expect(
      lines.where((Text t) => t.style?.color != null),
      hasLength(1),
      reason: 'exactly one layer is the fill',
    );
  });

  testWidgets('loads the full image for the one tile drawn large', (
    WidgetTester tester,
  ) async {
    // A thumbnail is sized for a tile in a row of five; across the width of a
    // tablet it is visibly blocky, which is what the band looked like on the
    // device. Every other tile on the wall must stay on the thumbnail.
    await _pumpGrid(tester, _sourceOf(6));
    await _settle(tester);

    final WallpaperTile featured = tester.widget<WallpaperTile>(
      find.byType(WallpaperTile).first,
    );
    expect(featured.quality, TileImageQuality.fullResolution);

    for (final WallpaperTile tile
        in tester
            .widgetList<WallpaperTile>(find.byType(WallpaperTile))
            .skip(1)) {
      expect(
        tile.quality,
        TileImageQuality.thumbnail,
        reason: tile.wallpaper.id,
      );
    }
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
      query: const SearchQuery(term: 'sunset', sorting: Sorting.toplist),
    );
    await _settle(tester);

    expect(find.byType(FeaturedWallpaper), findsNothing);
    expect(find.byType(WallpaperTile), findsNWidgets(6));
  });

  testWidgets('stays off a listing ordered by time rather than merit', (
    WidgetTester tester,
  ) async {
    // *Latest* is the case this rule exists for. Uploaders post in series, so
    // items 0 and 1 are routinely near-identical variations — and the band then
    // reads as a repeat of the tile beneath it even though the two are
    // different wallpapers. Reported from the device (`pog7ze` over `6lyp66`).
    await _pumpGrid(
      tester,
      _sourceOf(6),
      query: const SearchQuery(),
    );
    await _settle(tester);

    expect(find.byType(FeaturedWallpaper), findsNothing);
    expect(find.byType(WallpaperTile), findsNWidgets(6));
  });

  testWidgets('stays off a shuffled listing too', (WidgetTester tester) async {
    // Nothing to say about an item that is first by chance.
    await _pumpGrid(
      tester,
      _sourceOf(6),
      query: const SearchQuery(sorting: Sorting.random),
    );
    await _settle(tester);

    expect(find.byType(FeaturedWallpaper), findsNothing);
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

/// Defaults to a *ranked* listing, because that is where the band lives.
Future<void> _pumpGrid(
  WidgetTester tester,
  FakeWallpaperSource source, {
  SearchQuery query = const SearchQuery(sorting: Sorting.toplist),
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
