import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_wallhaven_api.dart';

const SearchQuery _nsfwQuery = SearchQuery(purity: PurityFilter({Purity.nsfw}));

void main() {
  group('SearchWallpapers', () {
    test('passes an sfw query straight through', () async {
      final FakeWallhavenApi api = FakeWallhavenApi();
      final SearchWallpapers search = SearchWallpapers(
        api: api,
        secrets: FakeSecretStore(),
      );

      await search(const SearchQuery(term: 'forest'));

      expect(api.receivedQueries.single.term, 'forest');
    });

    test(
      'refuses an nsfw query with no key, without calling the API',
      () async {
        final FakeWallhavenApi api = FakeWallhavenApi();
        final SearchWallpapers search = SearchWallpapers(
          api: api,
          secrets: FakeSecretStore(),
        );

        await expectLater(
          search(_nsfwQuery),
          throwsA(isA<InvalidApiKeyFailure>()),
        );
        // The point of the guard: don't spend one of the 45 req/min on a
        // guaranteed 401.
        expect(api.receivedQueries, isEmpty);
      },
    );

    test('allows an nsfw query once a key is stored', () async {
      final FakeWallhavenApi api = FakeWallhavenApi();
      final SearchWallpapers search = SearchWallpapers(
        api: api,
        secrets: FakeSecretStore(storedKey: 'wallhaven-key'),
      );

      await search(_nsfwQuery);

      expect(api.receivedQueries, hasLength(1));
    });
  });

  group('SearchWallpapers.nextPageAfter', () {
    test(
      'advances the page and carries the seed of a random listing',
      () async {
        final FakeWallhavenApi api = FakeWallhavenApi();
        final SearchWallpapers search = SearchWallpapers(
          api: api,
          secrets: FakeSecretStore(),
        );
        const WallpaperPage first = WallpaperPage(
          wallpapers: <Wallpaper>[],
          currentPage: 1,
          lastPage: 5,
          seed: 'xyz789',
        );

        await search.nextPageAfter(
          const SearchQuery(sorting: Sorting.random),
          first,
        );

        final SearchQuery sent = api.receivedQueries.single;
        expect(sent.page, 2);
        // Dropping the seed here would silently re-roll the shuffle and repeat
        // images the user already scrolled past.
        expect(sent.seed, 'xyz789');
      },
    );

    test('keeps the original query seed when the page carries none', () async {
      final FakeWallhavenApi api = FakeWallhavenApi();
      final SearchWallpapers search = SearchWallpapers(
        api: api,
        secrets: FakeSecretStore(),
      );
      const WallpaperPage first = WallpaperPage(
        wallpapers: <Wallpaper>[],
        currentPage: 3,
        lastPage: 9,
      );

      await search.nextPageAfter(
        const SearchQuery(sorting: Sorting.random, seed: 'from-query'),
        first,
      );

      final SearchQuery sent = api.receivedQueries.single;
      expect(sent.page, 4);
      expect(sent.seed, 'from-query');
    });
  });
}
