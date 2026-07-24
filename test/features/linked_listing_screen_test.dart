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
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/browse_filter_button.dart';
import 'package:tela/features/browse/browse_filter_scope.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/linked_listing_screen.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

void main() {
  testWidgets('a tag listing searches the exact tag and says what it is', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = _api();
    await _pumpListing(
      tester,
      source,
      const TagLink(WallpaperTag(id: 37, name: 'nature')),
    );

    expect(source.receivedQueries.single.term, 'id:37');
    expect(find.text('nature'), findsOneWidget);
    expect(find.text('Wallpapers with this tag'), findsOneWidget);
    expect(find.byType(WallpaperTile), findsOneWidget);
    expect(
      tester.widget<WallpaperGrid>(find.byType(WallpaperGrid)).galleryIdentity,
      'linked:tag:37',
    );
  });

  testWidgets('an uploader listing is their uploads, and never a profile', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = _api();
    await _pumpListing(tester, source, const UploaderLink('pym'));

    expect(source.receivedQueries.single.term, '@pym');
    expect(find.text('@pym'), findsOneWidget);
    // Wallhaven's API has no user endpoint. The screen must not imply one.
    expect(find.text('Uploads by this user'), findsOneWidget);
  });

  testWidgets('newest first, and fitted to the screen it is opened on', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = _api();
    await _pumpListing(tester, source, const UploaderLink('pym'));

    final SearchQuery query = source.receivedQueries.single;
    expect(query.sorting, Sorting.dateAdded);
    // Automatic is resolved into a real minimum by the screen it opened on.
    expect(query.resolution, isA<AtLeastResolution>());
  });

  testWidgets('the seed the link was followed under is what applies here', (
    WidgetTester tester,
  ) async {
    // The bug this pins: a tag followed mid-browse must inherit the listing the
    // user was actually on, not Browse's global filters. Here Browse is safe,
    // but the seed is a sketchy People + colour session — the seed must win, or
    // a sketchy→wallpaper→tag chain silently drops back to safe.
    final FakeWallpaperSource source = _api();
    await _pumpListing(
      tester,
      source,
      const UploaderLink('pym'),
      seed: SearchQuery(
        categories: const CategoryFilter(<Category>{Category.anime}),
        purity: const PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
        color: WallpaperColor('#0066cc'),
      ),
    );

    final SearchQuery query = source.receivedQueries.single;
    expect(query.categories.categories, <Category>{Category.anime});
    expect(query.purity.purities, <Purity>{Purity.sfw, Purity.sketchy});
    expect(query.color, WallpaperColor('#0066cc'));
  });

  testWidgets("with no seed, it falls back to Browse's own filters", (
    WidgetTester tester,
  ) async {
    // Arriving without an origin — a deep link, a curated shelf — still lands
    // in the user's current world, the same starting point arriving from
    // Browse gives. Read once at arrival, not watched (see below).
    final FakeWallpaperSource source = _api();
    final ProviderContainer container = _container(source);
    container
        .read(browseQueryProvider.notifier)
        .applyFilters(
          const SearchQuery(
            purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
          ),
        );

    await _pumpListing(
      tester,
      source,
      const UploaderLink('pym'),
      container: container,
    );

    expect(source.receivedQueries.single.purity.purities, <Purity>{
      Purity.sfw,
      Purity.sketchy,
    });
  });

  testWidgets('a later change to Browse does not reach into an open listing', (
    WidgetTester tester,
  ) async {
    // Inheriting is a starting point, not a subscription: the seed is read
    // once at arrival, so narrowing Browse behind this must not re-narrow it.
    final FakeWallpaperSource source = _api();
    final ProviderContainer container = _container(source);
    await _pumpListing(
      tester,
      source,
      const TagLink(WallpaperTag(id: 37, name: 'nature')),
      container: container,
    );

    container
        .read(browseQueryProvider.notifier)
        .applyFilters(
          const SearchQuery(
            categories: CategoryFilter(<Category>{Category.people}),
          ),
        );
    await tester.pumpAndSettle();

    // Still browsing under the defaults it opened on, not Browse's new People.
    expect(
      source.receivedQueries.last.categories.categories,
      const SearchQuery().categories.categories,
    );
  });

  testWidgets('a colour listing sends the colour and keeps the seed', (
    WidgetTester tester,
  ) async {
    // "More wallpapers in this colour" is a followed listing too: it sets the
    // colour param, drops the term, and keeps the purity the user was on — the
    // same inheritance every follow gets.
    final FakeWallpaperSource source = _api();
    await _pumpListing(
      tester,
      source,
      ColorLink(WallpaperColor('#0066cc')),
      seed: const SearchQuery(
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
      ),
    );

    final SearchQuery query = source.receivedQueries.single;
    expect(query.color, WallpaperColor('#0066cc'));
    expect(query.term, '');
    expect(query.sorting, Sorting.dateAdded);
    expect(query.purity.purities, <Purity>{Purity.sfw, Purity.sketchy});
    expect(
      tester.widget<WallpaperGrid>(find.byType(WallpaperGrid)).galleryIdentity,
      'linked:color:0066cc',
    );
  });

  testWidgets('offers a way to filter the listing', (
    WidgetTester tester,
  ) async {
    // Missing entirely until Wave 3: the filter sheet already knew every filter
    // this screen honours, but the only button that opened it was private to
    // BrowseScreen.
    await _pumpListing(
      tester,
      _api(),
      const TagLink(WallpaperTag(id: 37, name: 'nature')),
    );

    expect(find.byType(BrowseFilterButton), findsOneWidget);
  });

  testWidgets('filtering the listing re-queries it, and leaves browse alone', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = _api();
    final ProviderContainer container = _container(source);
    await _pumpListing(
      tester,
      source,
      const TagLink(WallpaperTag(id: 37, name: 'nature')),
      container: container,
    );

    _scope(tester).applyFilters(
      const SearchQuery(
        categories: CategoryFilter(<Category>{Category.people}),
      ),
    );
    await tester.pumpAndSettle();

    // The listing itself narrowed...
    expect(
      source.receivedQueries.last.categories.categories,
      <Category>{Category.people},
    );
    expect(source.receivedQueries.last.term, 'id:37');
    // ...and the tabs waiting underneath did not. A pushed listing is a detour:
    // Back must leave browse exactly as it was.
    expect(
      container.read(browseQueryProvider).categories.categories,
      const SearchQuery().categories.categories,
    );
  });

  testWidgets('resetting a listing puts the purity back to safe', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = _api();
    // A sketchy session, inherited into the listing on arrival as the seed.
    await _pumpListing(
      tester,
      source,
      const TagLink(WallpaperTag(id: 37, name: 'nature')),
      seed: const SearchQuery(
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
      ),
    );
    expect(source.receivedQueries.single.purity.purities, <Purity>{
      Purity.sfw,
      Purity.sketchy,
    });

    _scope(tester).clearFilters();
    await tester.pumpAndSettle();

    // Reset is the button that ends a sketchy session. Re-inheriting the seed
    // here would have left it sketchy.
    expect(source.receivedQueries.last.purity.purities, <Purity>{Purity.sfw});
  });
}

/// The screen answers [BrowseFilterScope] over its own state; this is the seam
/// the shared filter sheet writes through, driven directly here.
BrowseFilterScope _scope(WidgetTester tester) =>
    tester.state(find.byType(LinkedListingScreen)) as BrowseFilterScope;

FakeWallpaperSource _api() => FakeWallpaperSource(
  page: WallpaperPage(
    wallpapers: <Wallpaper>[_wallpaper()],
    hasMore: false,
    currentPage: 1,
    lastPage: 1,
  ),
);

ProviderContainer _container(FakeWallpaperSource source) {
  return ProviderContainer(
    overrides: <Override>[
      wallhavenSourceProvider.overrideWithValue(source),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      tagBlocklistRepositoryProvider.overrideWithValue(
        FakeTagBlocklistRepository(),
      ),
    ],
  );
}

/// Boots the real listing screen with the network replaced by [source].
Future<void> _pumpListing(
  WidgetTester tester,
  FakeWallpaperSource source,
  WallpaperLink link, {
  SearchQuery? seed,
  ProviderContainer? container,
}) async {
  final ProviderContainer scope = container ?? _container(source);
  addTearDown(scope.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: LinkedListingScreen(link: link, seed: seed),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Wallpaper _wallpaper() => Wallpaper(
  id: 'e7jvjd',
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
