import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/data/wallhaven/wallhaven_query.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/features/browse/browse_screen.dart';
import 'package:tela/features/browse/browse_search_field.dart';
import 'package:tela/features/browse/browse_sorting_button.dart';
import 'package:tela/features/browse/filter_sheet.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/settings/blocked_tags_providers.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

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

/// Boots the real BrowseScreen with the network replaced by [source].
Future<void> _pumpBrowse(
  WidgetTester tester,
  FakeWallpaperSource source, {
  String? storedKey,
  FakeSettingsRepository? settings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenSourceProvider.overrideWithValue(source),
        secretStoreProvider.overrideWithValue(
          FakeSecretStore(storedKey: storedKey),
        ),
        // Browse opens on whichever defaults the user chose, so it reads the
        // settings store. An empty one means tela's own still apply.
        settingsRepositoryProvider.overrideWithValue(
          settings ?? FakeSettingsRepository(),
        ),
        // Every search now reads the standing blocklist. Left unbound, it
        // opens the real database.
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
  // Not pumpAndSettle: the tiles' fade-in and the (stubbed) image fetch never
  // reach a quiescent frame in a test binding.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Boots BrowseScreen over an explicit [ProviderContainer], so a test can
/// reach behind the widget tree to mutate [blocklist] and invalidate
/// [blockedTagsProvider] the same way blocking a tag from the detail screen
/// does.
Future<ProviderContainer> _pumpBrowseWithContainer(
  WidgetTester tester,
  FakeWallpaperSource source,
  FakeTagBlocklistRepository blocklist,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      wallhavenSourceProvider.overrideWithValue(source),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      tagBlocklistRepositoryProvider.overrideWithValue(blocklist),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  testWidgets(
    'switching source visibly relabels and reloads an equal default query',
    (WidgetTester tester) async {
      final FakeWallpaperSource wallhaven = FakeWallpaperSource();
      final FakeWallpaperSource booru = FakeWallpaperSource(
        id: const SourceId('booru'),
        displayName: 'Booru',
        capabilities: narrowCapabilities,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          wallpaperSourcesProvider.overrideWithValue(<WallpaperSource>[
            wallhaven,
            booru,
          ]),
          secretStoreProvider.overrideWithValue(FakeSecretStore()),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          tagBlocklistRepositoryProvider.overrideWithValue(
            FakeTagBlocklistRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Wallhaven'), findsOneWidget);
      expect(wallhaven.receivedQueries, isNotEmpty);
      expect(booru.receivedQueries, isEmpty);

      await tester.tap(find.text('Wallhaven'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<SourceId>, 'Booru'),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Booru'), findsOneWidget);
      expect(booru.receivedQueries, isNotEmpty);
      expect(
        booru.receivedQueries.every(
          (SearchQuery query) => narrowCapabilities.sortsBy(query.sorting),
        ),
        isTrue,
      );
      await tester.tap(find.byType(BrowseSortingButton));
      await tester.pumpAndSettle();
      expect(find.text('Most viewed'), findsOneWidget);
      expect(find.text('Most favorited'), findsOneWidget);
      expect(find.text('Top'), findsNothing);
      expect(find.text('Hot'), findsNothing);
      expect(find.text('Random'), findsNothing);
    },
  );

  testWidgets('renders a tile per wallpaper returned by the API', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource(
      page: WallpaperPage(
        wallpapers: <Wallpaper>[_wallpaper('aaa111'), _wallpaper('bbb222')],
        hasMore: false,
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await _pumpBrowse(tester, source);

    expect(find.byType(WallpaperTile), findsNWidgets(2));
  });

  testWidgets('grids with the ratio-preserving thumb, never the cropped one', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource(
      page: WallpaperPage(
        wallpapers: <Wallpaper>[_wallpaper('aaa111')],
        hasMore: false,
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await _pumpBrowse(tester, source);

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
    final FakeWallpaperSource source = FakeWallpaperSource();

    await _pumpBrowse(tester, source);

    // Without this the grid fills with images too small to look sharp once
    // they're actually set as a wallpaper. `Automatic` is what says so, and the
    // screen is what answers it — the domain has no idea how big the screen is.
    final ResolutionFilter resolution = source.receivedQueries.first.resolution;
    expect(resolution, isA<AtLeastResolution>());
    final Resolution atLeast = (resolution as AtLeastResolution).minimum;
    expect(atLeast.width, greaterThan(0));
    expect(atLeast.height, greaterThan(0));
  });

  testWidgets('opens on Latest, and browses sfw with no key', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();

    await _pumpBrowse(tester, source);

    final SearchQueryFacts first = SearchQueryFacts(
      source.receivedQueries.first,
    );
    expect(first.sorting, 'date_added');
    expect(first.purity, '100');
  });

  testWidgets('withholds the explicit filter until a key is stored', (
    WidgetTester tester,
  ) async {
    await _pumpBrowse(tester, FakeWallpaperSource());

    await _openFilters(tester);

    // Wallhaven 401s an explicit listing with no key, so offering the chip
    // would only produce an error.
    expect(find.text('Safe'), findsOneWidget);
    expect(find.text('Explicit'), findsNothing);
  });

  testWidgets('a stored key unlocks the explicit filter, and it searches', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source, storedKey: 'abc123');

    await _openFilters(tester);
    await tester.tap(find.text('Explicit'));
    await tester.pump();
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Safe stays on, so this is the sfw+nsfw mask, and the grid re-queried
    // rather than sitting on its previous page.
    final SearchQueryFacts applied = SearchQueryFacts(
      source.receivedQueries.last,
    );
    expect(applied.purity, '101');
  });

  testWidgets('searching a term re-queries with it', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await tester.enterText(find.byType(TextField), 'sunset');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(source.receivedQueries.last.term, 'sunset');
  });

  testWidgets('a tag added in the sheet is folded into the grid query', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await tester.enterText(find.byType(TextField), 'sunset');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _openFilters(tester);
    final Finder tagField = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == 'Add a tag',
    );
    await tester.enterText(tagField, 'nature');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The tag rides in `q` beside the term the user typed, not in place of it —
    // this is the first filter tela builds a Wallhaven operator for.
    expect(SearchQueryFacts(source.receivedQueries.last).q, 'sunset +"nature"');
  });

  testWidgets('most viewed and most favorited are reachable listings', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    // Both have been in the Sorting enum since Wave 1 and could not be reached
    // at all: the tab *was* the sorting, and there were only four tabs.
    await _tapTab(tester, 'Most viewed');
    expect(SearchQueryFacts(source.receivedQueries.last).sorting, 'views');

    await _tapTab(tester, 'Most favorited');
    expect(SearchQueryFacts(source.receivedQueries.last).sorting, 'favorites');
  });

  testWidgets('a phone keeps the search field usable beside the cluster', (
    WidgetTester tester,
  ) async {
    // Spelled-out source and sorting buttons pushed a 360dp bar past its edge
    // and left the search field a sliver (2026-10-06). Four icons leave it
    // 112dp: the magnifier and a few characters of the term.
    _phoneViewport(tester);
    await _pumpBrowse(tester, FakeWallpaperSource());

    expect(find.byIcon(Icons.sort), findsOneWidget);
    expect(find.text('Latest'), findsNothing);
    expect(
      tester.getSize(find.byType(BrowseSearchField)).width,
      greaterThanOrEqualTo(100),
    );
  });

  testWidgets('withholds relevance until there is a term to rank against', (
    WidgetTester tester,
  ) async {
    await _pumpBrowse(tester, FakeWallpaperSource());

    // Wallhaven's `relevance` ranks against `q`. With no term it has nothing to
    // rank, so the tab would quietly be a listing of something else.
    expect(_offeredSortings(tester), isNot(contains('Relevance')));
    expect(_selectedTab(tester), 'Latest');
  });

  testWidgets('submitting a search lands on relevance', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _search(tester, 'sunset');

    // A search that left you on Latest would rank by upload date and take no
    // account of what you typed.
    expect(_selectedTab(tester), 'Relevance');
    expect(_sortingsRequested(source), contains('relevance'));
    expect(source.receivedQueries.last.term, 'sunset');
  });

  testWidgets('refining a search returns to relevance', (
    WidgetTester tester,
  ) async {
    await _pumpBrowse(tester, FakeWallpaperSource());

    await _search(tester, 'sunset');
    await _tapTab(tester, 'Top');
    expect(_selectedTab(tester), 'Top');

    await _search(tester, 'sunset beach');

    // A different path from the first search: relevance is already on screen,
    // so the tab list does not change shape and nothing rebuilds the tab
    // controller. It has to be moved by hand, and this is what catches it.
    expect(_selectedTab(tester), 'Relevance');
  });

  testWidgets('clearing the search keeps the listing you were on', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _search(tester, 'sunset');
    await _tapTab(tester, 'Top');
    await _clearSearch(tester);

    // Relevance vanishes with the term and every tab behind it shifts one place
    // left, so a controller that held its *index* would have moved the user
    // from Top to Hot without being asked. The selection is by sorting.
    expect(_offeredSortings(tester), isNot(contains('Relevance')));
    expect(_selectedTab(tester), 'Top');
    expect(SearchQueryFacts(source.receivedQueries.last).sorting, 'toplist');
    expect(source.receivedQueries.last.term, isEmpty);
  });

  testWidgets('clearing the search while on relevance falls back to latest', (
    WidgetTester tester,
  ) async {
    await _pumpBrowse(tester, FakeWallpaperSource());

    await _search(tester, 'sunset');
    expect(_selectedTab(tester), 'Relevance');

    await _clearSearch(tester);

    // The tab the user was standing on is the one that just disappeared.
    expect(_selectedTab(tester), 'Latest');
  });

  testWidgets('shows a localized message and a retry when the API fails', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource(
      failure: const NetworkFailure(),
    );

    await _pumpBrowse(tester, source);

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
    final FakeWallpaperSource source = FakeWallpaperSource();

    await _pumpBrowse(tester, source);

    // No `colors` at all, rather than an empty one — Wallhaven reads an empty
    // filter as matching nothing.
    expect(SearchQueryFacts(source.receivedQueries.first).colors, isNull);
  });

  testWidgets('picking a colour re-queries the grid with it', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    await _tapSwatch(tester, WallpaperColor('#0066cc'));
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Sent bare, and the grid actually re-fetched rather than leaving the old
    // page up under a filter that appears ignored.
    expect(SearchQueryFacts(source.receivedQueries.last).colors, '0066cc');
  });

  testWidgets('tapping the chosen colour again clears the filter', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    await _tapSwatch(tester, WallpaperColor('#0066cc'));
    await _tapSwatch(tester, WallpaperColor('#0066cc'));
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The colour must be removable, which is the whole reason SearchQuery has
    // withColor: copyWith cannot express "back to none".
    expect(SearchQueryFacts(source.receivedQueries.last).colors, isNull);
  });

  testWidgets('"Any color" clears a chosen colour', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    await _tapSwatch(tester, WallpaperColor('#ea4c88'));
    await tester.tap(find.text('Any color'));
    await tester.pump();
    await tester.tap(find.text('Show wallpapers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(SearchQueryFacts(source.receivedQueries.last).colors, isNull);
  });

  testWidgets('the apply button stays reachable under the colour palette', (
    WidgetTester tester,
  ) async {
    await _pumpBrowse(tester, FakeWallpaperSource());

    await _openFilters(tester);

    // The palette is 29 swatches tall. With the actions inside the scroll view
    // it pushed "Show wallpapers" off the bottom of the sheet — an apply button
    // you have to go looking for is one that doesn't get pressed.
    expect(find.text('Show wallpapers'), findsOne);
    expect(tester.getSize(find.text('Show wallpapers')).height, greaterThan(0));
  });

  testWidgets('saving the filters as a default keeps them, and browses on '
      'them', (WidgetTester tester) async {
    final FakeSettingsRepository settings = FakeSettingsRepository();
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source, settings: settings);

    await _openFilters(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Anime'));
    await tester.pump();
    await tester.tap(find.text('Save as default'));
    await tester.pumpAndSettle();

    // Kept, as the device's snapshot, and browsed on — a "save as default" that
    // left the grid on the old filters would be a button that does nothing.
    expect(settings.sourceSaved, BrowseDefaultsSource.device);
    expect(settings.deviceSaved?.categories.encodeStored(), '101');
    expect(source.receivedQueries.last.categories.encodeStored(), '101');
    expect(find.text('Saved as your browse defaults.'), findsOneWidget);
  });

  testWidgets('a saved default never carries a purity, so browse still opens '
      'on safe', (WidgetTester tester) async {
    final FakeSettingsRepository settings = FakeSettingsRepository();
    await _pumpBrowse(
      tester,
      FakeWallpaperSource(),
      storedKey: 'abc123',
      settings: settings,
    );

    await _openFilters(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Explicit'));
    await tester.pump();
    await tester.tap(find.text('Save as default'));
    await tester.pumpAndSettle();

    // The session keeps the explicit chip the user just pressed, but nothing
    // about it reaches the snapshot — the next launch opens on safe.
    expect(settings.deviceSaved, isNotNull);
    final SearchQuery reopened = settings.deviceSaved!.applyTo(
      const SearchQuery(),
    );
    expect(reopened.purity.purities, <Purity>{Purity.sfw});
  });

  testWidgets('offers the shape of the screen the user is actually holding', (
    WidgetTester tester,
  ) async {
    _phoneViewport(tester);
    await _pumpBrowse(tester, FakeWallpaperSource());

    await _openFilters(tester);

    // A 1080x2400 phone reduces to 9x20 — a shape in no wallpaper site's
    // dropdown, which Wallhaven honours anyway. That it can be offered at all
    // is the whole finding behind this filter.
    expect(find.text('9×20 · your screen'), findsOneWidget);
  });

  testWidgets('the ratio chips are a union: picking two asks for both', (
    WidgetTester tester,
  ) async {
    _phoneViewport(tester);
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    // Portrait 9x16 is on by default; add a second shape rather than replacing
    // it. This is the difference from the colour swatches, which are a radio
    // because `colors` matches one bucket at a time in the API.
    await _tapInSheet(tester, find.widgetWithText(FilterChip, '16×9'));
    await _applyFilters(tester);

    expect(SearchQueryFacts(source.receivedQueries.last).ratios, '9x16,16x9');
  });

  testWidgets('a keyword shape is offered beside the exact ones', (
    WidgetTester tester,
  ) async {
    _phoneViewport(tester);
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    // `portrait` is broader than any exact ratio and is not a synonym for one:
    // it returns everything taller than it is wide. It replaces the default
    // 9x16 rather than joining it: Wallhaven drops a keyword sent beside an
    // exact ratio, so `9x16,portrait` would have meant 9x16 alone.
    await _tapInSheet(tester, find.widgetWithText(FilterChip, 'Any portrait'));
    await _applyFilters(tester);

    expect(SearchQueryFacts(source.receivedQueries.last).ratios, 'portrait');
  });

  testWidgets('"Any shape" sends both shape keywords', (
    WidgetTester tester,
  ) async {
    _phoneViewport(tester);
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    await _tapInSheet(tester, find.widgetWithText(FilterChip, 'Any shape'));
    await _applyFilters(tester);

    // Spelled out, not omitted: a keyed request fills an absent `ratios` from
    // the account's settings. The last ratio chip *may* be turned off, unlike
    // the last category.
    expect(
      SearchQueryFacts(source.receivedQueries.last).ratios,
      'portrait,landscape',
    );
  });

  testWidgets('the resolution filter opens on Automatic, fitting the screen', (
    WidgetTester tester,
  ) async {
    _phoneViewport(tester);
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    final Finder hint = find.text(
      'Nothing smaller than this screen (1080×2400).',
    );
    await _revealInSheet(tester, hint);

    // The filter that used to be imposed rather than chosen. Automatic still
    // does exactly what the old hard-coded `atLeast` did, so a device that
    // upgrades browses exactly as it did yesterday.
    expect(hint, findsOneWidget);
    final SearchQueryFacts opening = SearchQueryFacts(
      source.receivedQueries.first,
    );
    expect(opening.atLeast, '1080x2400');
    expect(opening.resolutions, isNull);
  });

  testWidgets('"Exactly" sends `resolutions` and never `atleast` with it', (
    WidgetTester tester,
  ) async {
    _phoneViewport(tester);
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    await _tapInSheet(tester, find.text('Exactly'));
    await _applyFilters(tester);

    // The two params conflict on the real server — it honours `atleast` and
    // silently ignores `resolutions` — so sending both would be a filter that
    // appears ignored. Switching mode seeds with the screen, which is what
    // Automatic was already asking for.
    final SearchQueryFacts exact = SearchQueryFacts(
      source.receivedQueries.last,
    );
    expect(exact.resolutions, '1080x2400');
    expect(exact.atLeast, isNull);
  });

  testWidgets('"At least" re-queries with the size that was picked', (
    WidgetTester tester,
  ) async {
    _phoneViewport(tester);
    final FakeWallpaperSource source = FakeWallpaperSource();
    await _pumpBrowse(tester, source);

    await _openFilters(tester);
    await _tapInSheet(tester, find.text('At least'));
    await _tapInSheet(tester, find.widgetWithText(FilterChip, '1440×2560'));
    await _applyFilters(tester);

    final SearchQueryFacts atLeast = SearchQueryFacts(
      source.receivedQueries.last,
    );
    expect(atLeast.atLeast, '1440x2560');
    expect(atLeast.resolutions, isNull);
  });

  testWidgets(
    'blocking a tag silently re-fetches the grid already on screen',
    (WidgetTester tester) async {
      final FakeWallpaperSource source = FakeWallpaperSource(
        pageFor: (SearchQuery query) => query.blockedTagNames.isEmpty
            ? WallpaperPage(
                wallpapers: <Wallpaper>[
                  _wallpaper('aaa111'),
                  _wallpaper('bbb222'),
                ],
                hasMore: false,
                currentPage: 1,
                lastPage: 1,
              )
            : WallpaperPage(
                wallpapers: <Wallpaper>[_wallpaper('aaa111')],
                hasMore: false,
                currentPage: 1,
                lastPage: 1,
              ),
      );
      final FakeTagBlocklistRepository blocklist = FakeTagBlocklistRepository();
      final ProviderContainer container = await _pumpBrowseWithContainer(
        tester,
        source,
        blocklist,
      );

      expect(find.byType(WallpaperTile), findsNWidgets(2));

      await blocklist.block(const WallpaperTag(id: 9, name: 'spoilers'));
      container.invalidate(blockedTagsProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The grid re-fetched in place — no full-screen loading state, no
      // navigation, just fewer tiles than a moment ago.
      expect(find.byType(WallpaperTile), findsNWidgets(1));
    },
  );

  testWidgets(
    'the blocklist merely loading does not re-fetch the page already on screen',
    (WidgetTester tester) async {
      final FakeWallpaperSource source = FakeWallpaperSource(
        page: WallpaperPage(
          wallpapers: <Wallpaper>[_wallpaper('aaa111')],
          hasMore: false,
          currentPage: 1,
          lastPage: 1,
        ),
      );
      // The blocklist loses the race deliberately: it resolves with the first
      // page already on screen, which is when a re-fetch-on-first-resolution
      // has loaded pages to spend a request on. Resolving first, it would find
      // no pages and cost nothing, and this would pass either way. The delay
      // must outlast the 300ms _pumpBrowseWithContainer itself pumps, or the
      // baseline below is captured after the re-fetch it is meant to catch.
      final FakeTagBlocklistRepository blocklist = FakeTagBlocklistRepository(
        readDelay: const Duration(milliseconds: 600),
      );
      await _pumpBrowseWithContainer(tester, source, blocklist);
      expect(find.byType(WallpaperTile), findsOneWidget);
      final int afterFirstPage = source.receivedQueries.length;

      await tester.pump(const Duration(seconds: 1));

      // Nothing was blocked, so nothing changed, so nothing is worth asking
      // Wallhaven again — the opening fetch read this same empty blocklist.
      expect(source.receivedQueries, hasLength(afterFirstPage));
    },
  );
}

/// Types [term] into the search field and submits it, as the keyboard would.
Future<void> _search(WidgetTester tester, String term) async {
  await tester.enterText(find.byType(TextField), term);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await _settleTabs(tester);
}

/// Empties the search field from its own clear button.
Future<void> _clearSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Clear search'));
  await _settleTabs(tester);
}

/// Picks the sorting named [label] from the sorting menu.
Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.byType(BrowseSortingButton));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, label));
  await _settleTabs(tester);
}

/// Long enough for the page to finish sliding and the grid to fetch.
Future<void> _settleTabs(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The sorting the listing is actually on.
///
/// Read through the controller the button drives rather than an index this
/// test computed, because the index is exactly what the screen must *not* rely
/// on: Relevance appearing renumbers every sorting behind it.
String _selectedTab(WidgetTester tester) {
  final BrowseSortingButton button = tester.widget<BrowseSortingButton>(
    find.byType(BrowseSortingButton),
  );
  return _sortingNames[button.sortings[button.tabs.index]]!;
}

/// Every sorting the menu would offer, by label.
List<String> _offeredSortings(WidgetTester tester) {
  final BrowseSortingButton button = tester.widget<BrowseSortingButton>(
    find.byType(BrowseSortingButton),
  );
  return <String>[
    for (final Sorting sorting in button.sortings) _sortingNames[sorting]!,
  ];
}

const Map<Sorting, String> _sortingNames = <Sorting, String>{
  Sorting.dateAdded: 'Latest',
  Sorting.relevance: 'Relevance',
  Sorting.random: 'Random',
  Sorting.views: 'Most viewed',
  Sorting.favorites: 'Most favorited',
  Sorting.toplist: 'Top',
  Sorting.hot: 'Hot',
};

/// Every `sorting` Wallhaven was actually asked for, in order.
List<String?> _sortingsRequested(FakeWallpaperSource source) {
  return source.receivedQueries
      .map((SearchQuery query) => SearchQueryFacts(query).sorting)
      .toList();
}

/// Pretends the test is running on a 1080x2400 phone, until the test ends.
///
/// The default test viewport (800x600 at dpr 3) reduces to 4x3, which is one of
/// the standard shapes — so it could never show that the device's *own* ratio
/// is offered even when it is not a standard one. A real phone reduces to 9x20,
/// which appears in no dropdown and which Wallhaven honours anyway.
void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Taps something inside the filter sheet, scrolling it into view first.
///
/// The sheet is a [ListView]: a control below the fold is not merely
/// off-screen, it is *not built*, so a plain finder reports it missing rather
/// than hidden. And the scrollable is named explicitly, because the browse grid
/// is still mounted *behind* the sheet and is the first [Scrollable] in the
/// tree — the obvious `find.byType(Scrollable).first` drags the listing rather
/// than the sheet.
Future<void> _tapInSheet(WidgetTester tester, Finder target) async {
  await _revealInSheet(tester, target);
  await tester.tap(target);
  await tester.pump();
}

/// Scrolls the filter sheet until [target] is genuinely on screen.
///
/// Needed to *assert* on a control below the fold as much as to tap one: the
/// sheet is a [ListView], so a control down there is not built at all and a
/// finder reports it missing rather than merely off-screen.
Future<void> _revealInSheet(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find
        .descendant(
          of: find.byType(FilterSheet),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  // A ListView builds a little beyond its own viewport, so the scroll above
  // stops as soon as the target is *built* — while it is still clipped. A tap
  // on a clipped widget silently misses. This is what puts it on screen.
  await tester.ensureVisible(target);
  await tester.pump();
}

/// Applies the sheet's draft and lets the grid re-query.
Future<void> _applyFilters(WidgetTester tester) async {
  await tester.tap(find.text('Show wallpapers'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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
Future<void> _tapSwatch(WidgetTester tester, WallpaperColor color) {
  return _tapInSheet(tester, find.bySemanticsLabel('Color ${color.hex}'));
}

/// Reads the wire-level facts of a query without reaching into the API adapter.
class SearchQueryFacts {
  /// Encodes [query] the way the HTTP client would.
  SearchQueryFacts(SearchQuery query)
    : _params = wallhavenQueryParameters(query);

  final Map<String, String> _params;

  /// The `sorting` param.
  String? get sorting => _params['sorting'];

  /// The `purity` bit mask.
  String? get purity => _params['purity'];

  /// The `q` param — the free-text term with the sheet's tags folded in.
  String? get q => _params['q'];

  /// The `colors` param — bare hex, no leading `#`, absent when unfiltered.
  String? get colors => _params['colors'];

  /// The `ratios` param — comma-joined, both keywords for every shape.
  String? get ratios => _params['ratios'];

  /// The `atleast` param — the minimum size, absent under an exact filter.
  String? get atLeast => _params['atleast'];

  /// The `resolutions` param — exact sizes, absent under an at-least filter.
  /// Never present at the same time as [atLeast]; the server ignores it if so.
  String? get resolutions => _params['resolutions'];
}
