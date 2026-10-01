import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/tag_folder.dart';
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

import '../fakes/fake_download_history.dart';
import '../fakes/fake_download_queue.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_applier.dart';
import '../fakes/fake_wallpaper_sharer.dart';
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

  testWidgets('a download files under the tag being browsed, not the last', (
    WidgetTester tester,
  ) async {
    // The owner's report, in their words: "if I enter the pictures with tag
    // flower, then check the user pictures, then go to another tag like white
    // minimalist ... it just fixups on the flower tag" (2026-08-24). Every
    // download path used to ask `browseQueryProvider` what listing it was on —
    // and a followed listing keeps its filters in *this* screen's state, so
    // that provider still held whatever was last typed into the search box.
    final FakeWallpaperSource source = _api();
    final FakeImageStore images = FakeImageStore();
    final ProviderContainer scope = _container(source, images: images);
    // The stale listing, still on the Browse tabs underneath.
    scope.read(browseQueryProvider.notifier).search('flower');
    await _pumpListing(
      tester,
      source,
      const TagLink(WallpaperTag(id: 37, name: 'white minimalist')),
      container: scope,
    );

    await _quickDownload(tester);

    expect(images.receivedTag, TagFolder('white minimalist'));
  });

  testWidgets('a tag listing never files under the id it searches on', (
    WidgetTester tester,
  ) async {
    // The second half of the same bug, and the reason the link's own name has
    // to travel with the listing: `TagLink.narrow` sets the term to `id:37`,
    // which sanitizes into a perfectly legal folder called `id 37`. Handing
    // the listing's *query* to the chooser would have swapped one wrong answer
    // for another.
    final FakeWallpaperSource source = _api();
    final FakeImageStore images = FakeImageStore();
    await _pumpListing(
      tester,
      source,
      const TagLink(WallpaperTag(id: 37, name: 'nature')),
      container: _container(source, images: images),
    );

    await _quickDownload(tester);

    expect(images.receivedTag, TagFolder('nature'));
  });

  testWidgets("an uploader's listing files under their name", (
    WidgetTester tester,
  ) async {
    // "I am looking at Leo and I want these filed under it" — the case
    // `suggestTagFolders` already argued a listing answers for free, and the
    // one an uploader listing could not answer at all before this.
    final FakeWallpaperSource source = _api();
    final FakeImageStore images = FakeImageStore();
    await _pumpListing(
      tester,
      source,
      const UploaderLink('pym'),
      container: _container(source, images: images),
    );

    await _quickDownload(tester);

    expect(images.receivedTag, TagFolder('pym'));
  });

  testWidgets('download all on a tag asks no wallpaper what it is tagged', (
    WidgetTester tester,
  ) async {
    // The owner, 2026-09-30: on a tag listing "it still needs to check some
    // images to check the most taggable and i just want to use like
    // minimalist". The button sits in the app bar, above the grid's
    // `ListingOrigin`, so the chooser never heard the tag and fell back to a
    // tag lookup per wallpaper on the first page.
    final FakeWallpaperSource source = _api();
    await _pumpListing(
      tester,
      source,
      const TagLink(WallpaperTag(id: 37, name: 'minimalist')),
    );

    await tester.tap(find.byIcon(Icons.download_for_offline_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();

    expect(source.tagBudgets, isEmpty);
    expect(find.text('minimalist'), findsWidgets);
  });

  testWidgets('a colour listing names no folder, and invents none', (
    WidgetTester tester,
  ) async {
    // A colour has no word on screen — the title is a swatch — so there is
    // nothing to call a directory. Untagged is the honest answer.
    final FakeWallpaperSource source = _api();
    final FakeImageStore images = FakeImageStore();
    await _pumpListing(
      tester,
      source,
      ColorLink(WallpaperColor('#660000')),
      container: _container(source, images: images),
    );

    await _quickDownload(tester);

    expect(images.receivedTag, isNull);
  });

  testWidgets('an uploader listing is their uploads, and never a profile', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperSource source = _api();
    await _pumpListing(tester, source, const UploaderLink('pym'));

    expect(source.receivedQueries.single.term, isEmpty);
    expect(source.receivedQueries.single.uploader, 'pym');
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

ProviderContainer _container(
  FakeWallpaperSource source, {
  FakeImageStore? images,
}) {
  return ProviderContainer(
    overrides: <Override>[
      wallhavenSourceProvider.overrideWithValue(source),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      tagBlocklistRepositoryProvider.overrideWithValue(
        FakeTagBlocklistRepository(),
      ),
      // Only the download path below needs these; bound always so a test that
      // reaches one never opens the real database or method channel.
      imageStoreProvider.overrideWithValue(images ?? FakeImageStore()),
      downloadHistoryProvider.overrideWithValue(FakeDownloadHistory()),
      downloadQueueProvider.overrideWithValue(FakeDownloadQueue()),
      favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
      wallpaperApplierProvider.overrideWithValue(FakeWallpaperApplier()),
      wallpaperSharerProvider.overrideWithValue(FakeWallpaperSharer()),
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
      // A router, not `home:`: *Download all* captures `GoRouter.of` for its
      // *View* toast action before anything else runs.
      child: MaterialApp.router(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        routerConfig: GoRouter(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext context, GoRouterState state) =>
                  LinkedListingScreen(link: link, seed: seed),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Downloads the one tile on the listing through the wall's quick sheet.
///
/// The safe-wallpaper path, which asks nothing and files straight away — so
/// whatever folder it lands in is the one the code chose with no user in the
/// loop, which is exactly the question these tests ask.
Future<void> _quickDownload(WidgetTester tester) async {
  await tester.longPress(find.byType(WallpaperTile));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Download'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
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
