import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

void main() {
  group('PurityFilter.toApiBits', () {
    test('encodes in Wallhaven bit order: sfw sketchy nsfw', () {
      expect(PurityFilter.sfwOnly.toApiBits(), '100');
      expect(
        const PurityFilter({Purity.sfw, Purity.sketchy}).toApiBits(),
        '110',
      );
      expect(
        const PurityFilter({
          Purity.sfw,
          Purity.sketchy,
          Purity.nsfw,
        }).toApiBits(),
        '111',
      );
      // Non-contiguous selections must not collapse to a prefix.
      expect(const PurityFilter({Purity.nsfw}).toApiBits(), '001');
    });

    test('rejects an empty selection instead of sending "000"', () {
      expect(
        const PurityFilter(<Purity>{}).toApiBits,
        throwsA(isA<ArgumentError>()),
      );
    });

    test('knows when a key is needed', () {
      expect(PurityFilter.sfwOnly.requiresApiKey, isFalse);
      expect(const PurityFilter({Purity.nsfw}).requiresApiKey, isTrue);
    });
  });

  group('CategoryFilter.toApiBits', () {
    test('encodes in Wallhaven bit order: general anime people', () {
      expect(CategoryFilter.all.toApiBits(), '111');
      expect(const CategoryFilter({Category.general}).toApiBits(), '100');
      expect(const CategoryFilter({Category.people}).toApiBits(), '001');
    });

    test('rejects an empty selection', () {
      expect(
        const CategoryFilter(<Category>{}).toApiBits,
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SearchQuery.toQueryParameters', () {
    test('defaults to a safe, portrait, newest-first browse', () {
      final Map<String, String> params = const SearchQuery()
          .toQueryParameters();

      expect(params['purity'], '100');
      expect(params['categories'], '111');
      expect(params['sorting'], 'date_added');
      expect(params['order'], 'desc');
      expect(params['ratios'], '9x16');
      expect(params['page'], '1');
    });

    test('unions the ratios, because that is what the API does with them', () {
      final Map<String, String> params = const SearchQuery(
        ratios: <RatioChoice>[ExactRatio(9, 16), ShapeRatio.landscape],
      ).toQueryParameters();

      expect(params['ratios'], '9x16,landscape');
    });

    test('sends no `ratios` at all for "any shape"', () {
      // Not an empty `ratios=`, which is not how you ask for every shape.
      final Map<String, String> params = const SearchQuery(
        ratios: <RatioChoice>[],
      ).toQueryParameters();

      expect(params.containsKey('ratios'), isFalse);
    });

    test('never puts the API key in the query string', () {
      final Map<String, String> params = const SearchQuery(
        term: 'forest',
      ).toQueryParameters();

      expect(params.keys, isNot(contains('apikey')));
      expect(params.keys, isNot(contains('api_key')));
    });

    test('omits an empty term rather than sending q=', () {
      expect(const SearchQuery().toQueryParameters().containsKey('q'), isFalse);
      expect(const SearchQuery(term: 'cats').toQueryParameters()['q'], 'cats');
    });

    test('sends topRange only for toplist, which is the only sorting that '
        'honours it', () {
      final Map<String, String> hot = const SearchQuery(
        sorting: Sorting.hot,
      ).toQueryParameters();
      final Map<String, String> top = const SearchQuery(
        sorting: Sorting.toplist,
        topRange: TopRange.oneWeek,
      ).toQueryParameters();

      expect(hot.containsKey('topRange'), isFalse);
      expect(top['topRange'], '1w');
    });

    test('sends atleast only when set', () {
      expect(
        const SearchQuery().toQueryParameters().containsKey('atleast'),
        isFalse,
      );
      expect(
        const SearchQuery(
          resolution: AtLeastResolution(Resolution(1080, 2400)),
        ).toQueryParameters()['atleast'],
        '1080x2400',
      );
    });

    test(
      'carries the seed so a random listing does not reshuffle mid-scroll',
      () {
        final Map<String, String> params = const SearchQuery(
          sorting: Sorting.random,
          seed: 'abc123',
        ).toQueryParameters();

        expect(params['seed'], 'abc123');
      },
    );

    test('sends no colour at all when none is chosen', () {
      // Not an empty `colors=`, which Wallhaven reads as a filter that matches
      // nothing rather than as the absence of one.
      expect(
        const SearchQuery().toQueryParameters().containsKey('colors'),
        isFalse,
      );
    });

    test('sends a chosen colour without its leading hash', () {
      final Map<String, String> params = const SearchQuery()
          .withColor(WallpaperColor('#0066cc'))
          .toQueryParameters();

      expect(params['colors'], '0066cc');
    });
  });

  group('SearchQuery equality', () {
    test('two queries with the same filters are the same query', () {
      const SearchQuery one = SearchQuery(
        term: 'sunset',
        purity: PurityFilter({Purity.sfw, Purity.nsfw}),
        categories: CategoryFilter({Category.anime}),
        resolution: AtLeastResolution(Resolution(1080, 2400)),
      );
      const SearchQuery same = SearchQuery(
        term: 'sunset',
        purity: PurityFilter({Purity.nsfw, Purity.sfw}),
        categories: CategoryFilter({Category.anime}),
        resolution: AtLeastResolution(Resolution(1080, 2400)),
      );

      // Set members in a different order are the same filter. Without this the
      // browse grid would treat every rebuild as a new listing and re-fetch.
      expect(one, same);
      expect(one.hashCode, same.hashCode);
    });

    test('a changed filter is a different query', () {
      const SearchQuery sfw = SearchQuery();
      const SearchQuery nsfw = SearchQuery(
        purity: PurityFilter({Purity.nsfw}),
      );

      expect(sfw, isNot(nsfw));
      expect(const SearchQuery(term: 'cats'), isNot(const SearchQuery()));
      expect(const SearchQuery().atPage(2), isNot(const SearchQuery()));
      expect(
        const SearchQuery(ratios: <RatioChoice>[ExactRatio(16, 9)]),
        isNot(const SearchQuery()),
      );
      expect(
        const SearchQuery().withColor(WallpaperColor('#0066cc')),
        isNot(const SearchQuery()),
      );
    });

    test('two queries filtered by the same colour are the same query', () {
      final SearchQuery one = const SearchQuery().withColor(
        WallpaperColor('#0066cc'),
      );
      final SearchQuery same = const SearchQuery().withColor(
        WallpaperColor('#0066cc'),
      );

      expect(one, same);
      expect(one.hashCode, same.hashCode);
    });
  });

  group('SearchQuery.withColor', () {
    test('clears the colour, which copyWith structurally cannot', () {
      // copyWith fills an omitted argument from `this`, so it reads a null
      // colour as "leave it alone". Deselecting the swatch needs a call that
      // can mean "no colour" — without this the filter would be unremovable.
      final SearchQuery filtered = const SearchQuery().withColor(
        WallpaperColor('#0066cc'),
      );

      expect(filtered.copyWith().color, WallpaperColor('#0066cc'));
      expect(filtered.withColor(null).color, isNull);
      expect(
        filtered.withColor(null).toQueryParameters().containsKey('colors'),
        isFalse,
      );
    });

    test('leaves every other filter alone', () {
      const SearchQuery query = SearchQuery(
        term: 'sunset',
        sorting: Sorting.toplist,
        purity: PurityFilter({Purity.sketchy}),
        categories: CategoryFilter({Category.anime}),
        resolution: AtLeastResolution(Resolution(1080, 2400)),
        ratios: <RatioChoice>[ExactRatio(16, 9)],
        page: 3,
        seed: 'abc123',
      );

      final SearchQuery colored = query.withColor(WallpaperColor('#ea4c88'));

      expect(colored.withColor(null), query);
      expect(colored.term, 'sunset');
      expect(colored.sorting, Sorting.toplist);
      expect(colored.page, 3);
      expect(colored.seed, 'abc123');
    });
  });

  group('Resolution', () {
    test("parses Wallhaven's WxH form", () {
      expect(Resolution.parse('1920x1080'), const Resolution(1920, 1080));
    });

    test('rejects malformed input naming the offending value', () {
      expect(() => Resolution.parse('1920'), throwsA(isA<ArgumentError>()));
      expect(() => Resolution.parse('axb'), throwsA(isA<ArgumentError>()));
      expect(() => Resolution.parse('0x100'), throwsA(isA<ArgumentError>()));
    });

    test('knows portrait from landscape', () {
      expect(const Resolution(1080, 2400).isPortrait, isTrue);
      expect(const Resolution(1920, 1080).isPortrait, isFalse);
    });
  });
}
