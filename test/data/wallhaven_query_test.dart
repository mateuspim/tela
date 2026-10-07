import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/wallhaven/wallhaven_query.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

void main() {
  group('wallhavenPurityBits', () {
    test('encodes in Wallhaven bit order: sfw sketchy nsfw', () {
      expect(wallhavenPurityBits(PurityFilter.sfwOnly), '100');
      expect(
        wallhavenPurityBits(const PurityFilter({Purity.sfw, Purity.sketchy})),
        '110',
      );
      expect(
        wallhavenPurityBits(
          const PurityFilter({
            Purity.sfw,
            Purity.sketchy,
            Purity.nsfw,
          }),
        ),
        '111',
      );
      // Non-contiguous selections must not collapse to a prefix.
      expect(wallhavenPurityBits(const PurityFilter({Purity.nsfw})), '001');
    });

    test('rejects an empty selection instead of sending "000"', () {
      expect(
        () => wallhavenPurityBits(const PurityFilter(<Purity>{})),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('knows when a key is needed', () {
      expect(PurityFilter.sfwOnly.requiresApiKey, isFalse);
      expect(const PurityFilter({Purity.nsfw}).requiresApiKey, isTrue);
    });
  });

  group('wallhavenCategoryBits', () {
    test('encodes in Wallhaven bit order: general anime people', () {
      expect(wallhavenCategoryBits(CategoryFilter.all), '111');
      expect(
        wallhavenCategoryBits(const CategoryFilter({Category.general})),
        '100',
      );
      expect(
        wallhavenCategoryBits(const CategoryFilter({Category.people})),
        '001',
      );
    });

    test('rejects an empty selection', () {
      expect(
        () => wallhavenCategoryBits(const CategoryFilter(<Category>{})),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('wallhavenQueryParameters', () {
    test('defaults to a safe, portrait, newest-first browse', () {
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(),
      );

      expect(params['purity'], '100');
      expect(params['categories'], '111');
      expect(params['sorting'], 'date_added');
      expect(params['order'], 'desc');
      expect(params['ratios'], '9x16');
      expect(params['page'], '1');
    });

    test('unions the ratios, because that is what the API does with them', () {
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          ratios: <RatioChoice>[ExactRatio(9, 16), ExactRatio(9, 20)],
        ),
      );

      expect(params['ratios'], '9x16,9x20');
    });

    test('sends both shape keywords for "any shape"', () {
      // Regression: omitting `ratios` lets a keyed request fall back to the
      // account's saved ratios, which overrode a device default of "any".
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          ratios: <RatioChoice>[],
        ),
      );

      expect(params['ratios'], 'portrait,landscape');
    });

    test('never puts the API key in the query string', () {
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          term: 'forest',
        ),
      );

      expect(params.keys, isNot(contains('apikey')));
      expect(params.keys, isNot(contains('api_key')));
    });

    test('omits an empty term rather than sending q=', () {
      expect(
        wallhavenQueryParameters(const SearchQuery()).containsKey('q'),
        isFalse,
      );
      expect(
        wallhavenQueryParameters(const SearchQuery(term: 'cats'))['q'],
        'cats',
      );
    });

    test('encodes a structural uploader with Wallhaven syntax', () {
      expect(
        wallhavenQueryParameters(
          const SearchQuery(uploader: 'pym'),
        )['q'],
        '@pym',
      );
    });

    test('sends topRange only for toplist, which is the only sorting that '
        'honours it', () {
      final Map<String, String> hot = wallhavenQueryParameters(
        const SearchQuery(
          sorting: Sorting.hot,
        ),
      );
      final Map<String, String> top = wallhavenQueryParameters(
        const SearchQuery(
          sorting: Sorting.toplist,
          topRange: TopRange.oneWeek,
        ),
      );

      expect(hot.containsKey('topRange'), isFalse);
      expect(top['topRange'], '1w');
    });

    test('sends atleast only when set', () {
      expect(
        wallhavenQueryParameters(const SearchQuery()).containsKey('atleast'),
        isFalse,
      );
      expect(
        wallhavenQueryParameters(
          const SearchQuery(
            resolution: AtLeastResolution(Resolution(1080, 2400)),
          ),
        )['atleast'],
        '1080x2400',
      );
    });

    test(
      'carries the seed so a random listing does not reshuffle mid-scroll',
      () {
        final Map<String, String> params = wallhavenQueryParameters(
          const SearchQuery(
            sorting: Sorting.random,
            seed: 'abc123',
          ),
        );

        expect(params['seed'], 'abc123');
      },
    );

    test('folds the tags into q, after the free-text term', () {
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          term: 'sunset',
          tags: <SearchTag>[
            SearchTag('nature'),
            SearchTag('people', TagSense.exclude),
          ],
        ),
      );

      expect(params['q'], 'sunset +"nature" -"people"');
    });

    test('sends a tag-only q with no free-text term', () {
      // A leading + is a query Wallhaven accepts; the tag alone is still a
      // search, not a browse.
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          tags: <SearchTag>[SearchTag('nature')],
        ),
      );

      expect(params['q'], '+"nature"');
    });

    test('sends id: alone, withholding tags and the blocklist', () {
      // Confirmed live against Wallhaven (2026-07-15): id:{n} returns *zero*
      // results the moment anything else shares q with it — this is what
      // made following a tag chip go blank the instant one tag was blocked.
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          term: 'id:37',
          tags: <SearchTag>[SearchTag('nature')],
          blockedTagNames: <String>{'spoilers'},
        ),
      );

      expect(params['q'], 'id:37');
    });

    test('sends like: alone, withholding tags and the blocklist', () {
      // Same exclusive-operator rule as id:, confirmed live the same way.
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          term: 'like:123',
          tags: <SearchTag>[SearchTag('nature')],
          blockedTagNames: <String>{'spoilers'},
        ),
      );

      expect(params['q'], 'like:123');
    });

    test('sends no q at all for a browse with no term and no tags', () {
      expect(
        wallhavenQueryParameters(const SearchQuery()).containsKey('q'),
        isFalse,
      );
    });

    test('folds the blocklist into q, as -name after the tags', () {
      // Not -id:{n}: confirmed live against Wallhaven (2026-07-15) that the
      // exact-id operator has no exclude side and is silently ignored, where
      // -name genuinely filters.
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          term: 'sunset',
          tags: <SearchTag>[SearchTag('nature')],
          blockedTagNames: <String>{'spoilers'},
        ),
      );

      expect(params['q'], 'sunset +"nature" -"spoilers"');
    });

    test('sends a blocklist-only q with no term and no tags', () {
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          blockedTagNames: <String>{'spoilers'},
        ),
      );

      expect(params['q'], '-"spoilers"');
    });

    test('quotes a multi-word blocked tag name, not just single words', () {
      // The bug this guards: unquoted, Wallhaven reads `-anime girls` as
      // excluding "anime" *and* weakly matching the bare word "girls" —
      // never as excluding the one tag. Two of those stacked crushed a real
      // listing to near zero (found live, 2026-07-15).
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery(
          blockedTagNames: <String>{'anime girls'},
        ),
      );

      expect(params['q'], '-"anime girls"');
    });

    test('sends no colour at all when none is chosen', () {
      // Not an empty `colors=`, which Wallhaven reads as a filter that matches
      // nothing rather than as the absence of one.
      expect(
        wallhavenQueryParameters(const SearchQuery()).containsKey('colors'),
        isFalse,
      );
    });

    test('sends a chosen colour without its leading hash', () {
      final Map<String, String> params = wallhavenQueryParameters(
        const SearchQuery().withColor(WallpaperColor('#0066cc')),
      );

      expect(params['colors'], '0066cc');
    });
  });
}
