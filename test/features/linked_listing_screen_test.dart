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
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/linked_listing_screen.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallhaven_api.dart';

void main() {
  testWidgets('a tag listing searches the exact tag and says what it is', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = _api();
    await _pumpListing(
      tester,
      api,
      const TagLink(WallpaperTag(id: 37, name: 'nature')),
    );

    expect(api.receivedQueries.single.term, 'id:37');
    expect(find.text('nature'), findsOneWidget);
    expect(find.text('Wallpapers with this tag'), findsOneWidget);
    expect(find.byType(WallpaperTile), findsOneWidget);
  });

  testWidgets('an uploader listing is their uploads, and never a profile', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = _api();
    await _pumpListing(tester, api, const UploaderLink('pym'));

    expect(api.receivedQueries.single.term, '@pym');
    expect(find.text('@pym'), findsOneWidget);
    // Wallhaven's API has no user endpoint. The screen must not imply one.
    expect(find.text('Uploads by this user'), findsOneWidget);
  });

  testWidgets('newest first, and fitted to the screen it is opened on', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = _api();
    await _pumpListing(tester, api, const UploaderLink('pym'));

    final SearchQuery query = api.receivedQueries.single;
    expect(query.sorting, Sorting.dateAdded);
    expect(query.atLeast, isNotNull);
  });

  testWidgets('the filters the user is browsing under still apply here', (
    WidgetTester tester,
  ) async {
    final FakeWallhavenApi api = _api();
    final ProviderContainer container = _container(api);
    // The listing is reached from a wallpaper, mid-browse — so it inherits the
    // listing the user is already on. Only the term and the sorting are the
    // link's. Following a tag must not quietly widen a filter they set.
    container
        .read(browseQueryProvider.notifier)
        .applyFilters(
          SearchQuery(
            categories: const CategoryFilter(<Category>{Category.anime}),
            purity: const PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
            color: WallpaperColor('#0066cc'),
          ),
        );

    await _pumpListing(
      tester,
      api,
      const UploaderLink('pym'),
      container: container,
    );

    final SearchQuery query = api.receivedQueries.single;
    expect(query.categories.categories, <Category>{Category.anime});
    expect(query.purity.purities, <Purity>{Purity.sfw, Purity.sketchy});
    expect(query.color, WallpaperColor('#0066cc'));
  });
}

FakeWallhavenApi _api() => FakeWallhavenApi(
  page: WallpaperPage(
    wallpapers: <Wallpaper>[_wallpaper()],
    currentPage: 1,
    lastPage: 1,
  ),
);

ProviderContainer _container(FakeWallhavenApi api) {
  return ProviderContainer(
    overrides: <Override>[
      wallhavenApiProvider.overrideWithValue(api),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
    ],
  );
}

/// Boots the real listing screen with the network replaced by [api].
Future<void> _pumpListing(
  WidgetTester tester,
  FakeWallhavenApi api,
  WallpaperLink link, {
  ProviderContainer? container,
}) async {
  final ProviderContainer scope = container ?? _container(api);
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
        home: LinkedListingScreen(link: link),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Wallpaper _wallpaper() => const Wallpaper(
  id: 'e7jvjd',
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: <String>[],
);
