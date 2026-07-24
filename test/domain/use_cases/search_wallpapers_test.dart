import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallhaven/wallhaven_query.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_tag_blocklist_repository.dart';
import '../../fakes/fake_wallhaven_api.dart';

const SearchQuery _nsfwQuery = SearchQuery(purity: PurityFilter({Purity.nsfw}));

void main() {
  group('SearchWallpapers', () {
    test('passes an sfw query straight through', () async {
      final FakeWallhavenApi api = FakeWallhavenApi();
      final SearchWallpapers search = SearchWallpapers(
        api: api,
        secrets: FakeSecretStore(),
        blocklist: FakeTagBlocklistRepository(),
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
          blocklist: FakeTagBlocklistRepository(),
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
        blocklist: FakeTagBlocklistRepository(),
      );

      await search(_nsfwQuery);

      expect(api.receivedQueries, hasLength(1));
    });

    test('folds the standing blocklist into every query as -name', () async {
      // Not -id:{n}: confirmed live against Wallhaven that the exact-id
      // operator has no exclude side and is silently ignored.
      final FakeWallhavenApi api = FakeWallhavenApi();
      final SearchWallpapers search = SearchWallpapers(
        api: api,
        secrets: FakeSecretStore(),
        blocklist: FakeTagBlocklistRepository(
          initial: const <WallpaperTag>[WallpaperTag(id: 37, name: 'nature')],
        ),
      );

      await search(const SearchQuery(term: 'forest'));

      final SearchQuery sent = api.receivedQueries.single;
      expect(sent.blockedTagNames, <String>{'nature'});
      expect(wallhavenQueryParameters(sent)['q'], 'forest -"nature"');
    });

    test('sends no exclude at all with an empty blocklist', () async {
      final FakeWallhavenApi api = FakeWallhavenApi();
      final SearchWallpapers search = SearchWallpapers(
        api: api,
        secrets: FakeSecretStore(),
        blocklist: FakeTagBlocklistRepository(),
      );

      await search(const SearchQuery(term: 'forest'));

      expect(api.receivedQueries.single.blockedTagNames, isEmpty);
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
          blocklist: FakeTagBlocklistRepository(),
        );
        const WallpaperPage first = WallpaperPage(
          wallpapers: <Wallpaper>[],
          hasMore: true,
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
        blocklist: FakeTagBlocklistRepository(),
      );
      const WallpaperPage first = WallpaperPage(
        wallpapers: <Wallpaper>[],
        hasMore: true,
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

    test('carries the blocklist into the next page too', () async {
      final FakeWallhavenApi api = FakeWallhavenApi();
      final SearchWallpapers search = SearchWallpapers(
        api: api,
        secrets: FakeSecretStore(),
        blocklist: FakeTagBlocklistRepository(
          initial: const <WallpaperTag>[WallpaperTag(id: 9, name: 'spoilers')],
        ),
      );
      const WallpaperPage first = WallpaperPage(
        wallpapers: <Wallpaper>[],
        hasMore: true,
        currentPage: 1,
        lastPage: 5,
      );

      await search.nextPageAfter(const SearchQuery(), first);

      expect(api.receivedQueries.single.blockedTagNames, <String>{'spoilers'});
    });
  });
}
