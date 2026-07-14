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
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/browse_screen.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
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
Future<void> _pumpBrowse(
  WidgetTester tester,
  FakeWallhavenApi api, {
  String? storedKey,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenApiProvider.overrideWithValue(api),
        secretStoreProvider.overrideWithValue(
          FakeSecretStore(storedKey: storedKey),
        ),
        // Browse opens on the synced account defaults, so it reads the settings
        // store. This one is empty: the app's own defaults still apply.
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
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

  testWidgets('withholds the explicit filter until a key is stored', (
    WidgetTester tester,
  ) async {
    await _pumpBrowse(tester, FakeWallhavenApi());

    await _openFilters(tester);

    // Wallhaven 401s an explicit listing with no key, so offering the chip
    // would only produce an error.
    expect(find.text('Safe'), findsOneWidget);
    expect(find.text('Explicit'), findsNothing);
  });

  testWidgets('a stored key unlocks the explicit filter, and it searches', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi();
    await _pumpBrowse(tester, api, storedKey: 'abc123');

    await _openFilters(tester);
    await tester.tap(find.text('Explicit'));
    await tester.pump();
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Safe stays on, so this is the sfw+nsfw mask, and the grid re-queried
    // rather than sitting on its previous page.
    final SearchQueryFacts applied = SearchQueryFacts(api.receivedQueries.last);
    expect(applied.purity, '101');
  });

  testWidgets('searching a term re-queries with it', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi();
    await _pumpBrowse(tester, api);

    await tester.enterText(find.byType(TextField), 'sunset');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.receivedQueries.last.term, 'sunset');
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
    // The offline icon, not the generic error one: a dead network is the one
    // failure the user can actually do something about.
    expect(find.byIcon(Icons.cloud_off_outlined), findsOne);
  });

  testWidgets('browses every colour until a swatch is picked', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi();

    await _pumpBrowse(tester, api);

    // No `colors` at all, rather than an empty one — Wallhaven reads an empty
    // filter as matching nothing.
    expect(SearchQueryFacts(api.receivedQueries.first).colors, isNull);
  });

  testWidgets('picking a colour re-queries the grid with it', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi();
    await _pumpBrowse(tester, api);

    await _openFilters(tester);
    await _tapSwatch(tester, WallpaperColor('#0066cc'));
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Sent bare, and the grid actually re-fetched rather than leaving the old
    // page up under a filter that appears ignored.
    expect(SearchQueryFacts(api.receivedQueries.last).colors, '0066cc');
  });

  testWidgets('tapping the chosen colour again clears the filter', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi();
    await _pumpBrowse(tester, api);

    await _openFilters(tester);
    await _tapSwatch(tester, WallpaperColor('#0066cc'));
    await _tapSwatch(tester, WallpaperColor('#0066cc'));
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The colour must be removable, which is the whole reason SearchQuery has
    // withColor: copyWith cannot express "back to none".
    expect(SearchQueryFacts(api.receivedQueries.last).colors, isNull);
  });

  testWidgets('"Any color" clears a chosen colour', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = FakeWallhavenApi();
    await _pumpBrowse(tester, api);

    await _openFilters(tester);
    await _tapSwatch(tester, WallpaperColor('#ea4c88'));
    await tester.tap(find.text('Any color'));
    await tester.pump();
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(SearchQueryFacts(api.receivedQueries.last).colors, isNull);
  });

  testWidgets('the apply button stays reachable under the colour palette', (
    WidgetTester tester,
  ) async {
    await _pumpBrowse(tester, FakeWallhavenApi());

    await _openFilters(tester);

    // The palette is 29 swatches tall. With the actions inside the scroll view
    // it pushed "Show wallpapers" off the bottom of the sheet — an apply button
    // you have to go looking for is one that doesn't get pressed.
    expect(find.text('Show wallpapers'), findsOne);
    expect(tester.getSize(find.text('Show wallpapers')).height, greaterThan(0));
  });
}

/// Opens the filter sheet from the browse app bar.
Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Filters'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Taps one palette swatch, found the way a screen reader would reach it.
///
/// The swatches have no text — the hex in their semantics label is the only
/// name they have, which is exactly why they carry one.
Future<void> _tapSwatch(WidgetTester tester, WallpaperColor color) async {
  await tester.tap(
    find.bySemanticsLabel('Color ${color.hex}'),
    warnIfMissed: false,
  );
  await tester.pump();
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

  /// The `colors` param — bare hex, no leading `#`, absent when unfiltered.
  String? get colors => _params['colors'];
}
