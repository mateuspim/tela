import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/browse_screen.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_wallhaven_api.dart';

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

/// Boots the real BrowseScreen with the network replaced by [api].
Future<void> _pumpBrowse(WidgetTester tester, FakeWallhavenApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(api),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
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
  // Not pumpAndSettle: the tiles' fade-in and the (stubbed) image fetch never
  // reach a quiescent frame in a test binding.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('renders a tile per wallpaper returned by the API', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi(
      page: WallpaperPage(
        wallpapers: <Wallpaper>[_wallpaper('aaa111'), _wallpaper('bbb222')],
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await _pumpBrowse(tester, api);

    expect(find.byType(WallpaperTile), findsNWidgets(2));
  });

  testWidgets('grids with the ratio-preserving thumb, never the cropped one', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi(
      page: WallpaperPage(
        wallpapers: <Wallpaper>[_wallpaper('aaa111')],
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await _pumpBrowse(tester, api);

    // Wallhaven crops small/large to a fixed 300x200. Rendering those inside a
    // box shaped by the wallpaper's real ratio turns a landscape into a
    // center-punched close-up — which is exactly what shipped on the first run.
    final CachedNetworkImage image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, contains('/orig/'));
  });

  testWidgets('asks for images at least as large as the device screen', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi();

    await _pumpBrowse(tester, api);

    // Without this the grid fills with images too small to look sharp once
    // they're actually set as a wallpaper.
    final Resolution? atLeast = api.receivedQueries.first.atLeast;
    expect(atLeast, isNotNull);
    expect(atLeast!.width, greaterThan(0));
    expect(atLeast.height, greaterThan(0));
  });

  testWidgets('opens on Latest, and browses sfw with no key', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi();

    await _pumpBrowse(tester, api);

    final SearchQueryFacts first = SearchQueryFacts(api.receivedQueries.first);
    expect(first.sorting, 'date_added');
    expect(first.purity, '100');
  });

  testWidgets('shows a localized message and a retry when the API fails', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi(
      failure: const NetworkFailure(),
    );

    await _pumpBrowse(tester, api);

    expect(
      find.text("Can't reach Wallhaven. Check your connection."),
      findsOne,
    );
    expect(find.text('Retry'), findsOne);
  });
}

/// Reads the wire-level facts of a query without reaching into the API adapter.
class SearchQueryFacts {
  /// Encodes [query] the way the HTTP client would.
  SearchQueryFacts(SearchQuery query) : _params = query.toQueryParameters();

  final Map<String, String> _params;

  /// The `sorting` param.
  String? get sorting => _params['sorting'];

  /// The `purity` bit mask.
  String? get purity => _params['purity'];
}
