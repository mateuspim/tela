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
  group('PurityFilter', () {
    test('knows when a key is needed', () {
      expect(PurityFilter.sfwOnly.requiresApiKey, isFalse);
      expect(const PurityFilter({Purity.nsfw}).requiresApiKey, isTrue);
    });
  });

  group('SearchQuery.key', () {
    test('is the same string for two queries that are one listing', () {
      // Tags and ratios are sets in meaning, so their order must not reach the
      // key — a shelf keyed by it would otherwise reload on a reordering.
      const SearchQuery one = SearchQuery(
        tags: <SearchTag>[SearchTag('nature'), SearchTag('forest')],
        purity: PurityFilter({Purity.sfw, Purity.sketchy}),
      );
      const SearchQuery other = SearchQuery(
        tags: <SearchTag>[SearchTag('forest'), SearchTag('nature')],
        purity: PurityFilter({Purity.sketchy, Purity.sfw}),
      );

      expect(one.key, other.key);
    });

    test('a changed filter is a different listing', () {
      expect(
        const SearchQuery().key,
        isNot(const SearchQuery(sorting: Sorting.toplist).key),
      );
      expect(
        const SearchQuery().key,
        isNot(const SearchQuery(term: 'cats').key),
      );
    });

    test('carries no source URL shape at all', () {
      // The point of the move: a shelf identity that named Wallhaven's params
      // made a feature file depend on them, and would have given two sources
      // one identity for the same filters.
      final String key = const SearchQuery(term: 'cats').key;

      expect(key, contains('term=cats'));
      expect(key, isNot(contains('q=')));
      expect(key, isNot(contains('100')));
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
      expect(const SearchQuery(uploader: 'pym'), isNot(const SearchQuery()));
      expect(const SearchQuery().atPage(2), isNot(const SearchQuery()));
      expect(
        const SearchQuery(ratios: <RatioChoice>[ExactRatio(16, 9)]),
        isNot(const SearchQuery()),
      );
      expect(
        const SearchQuery().withColor(WallpaperColor('#0066cc')),
        isNot(const SearchQuery()),
      );
      expect(
        const SearchQuery(tags: <SearchTag>[SearchTag('nature')]),
        isNot(const SearchQuery()),
      );
      expect(
        const SearchQuery(blockedTagNames: <String>{'spoilers'}),
        isNot(const SearchQuery()),
      );
    });

    test('the same tags in a different order are the same listing', () {
      const SearchQuery one = SearchQuery(
        tags: <SearchTag>[SearchTag('nature'), SearchTag('sky')],
      );
      const SearchQuery same = SearchQuery(
        tags: <SearchTag>[SearchTag('sky'), SearchTag('nature')],
      );

      // `+a +b` and `+b +a` are one Wallhaven request, so the grid must not
      // treat reordering them as a new listing and re-fetch.
      expect(one, same);
      expect(one.hashCode, same.hashCode);
    });

    test('the same blocklist in a different order is the same listing', () {
      const SearchQuery one = SearchQuery(
        blockedTagNames: <String>{'spoilers', 'gore'},
      );
      const SearchQuery same = SearchQuery(
        blockedTagNames: <String>{'gore', 'spoilers'},
      );

      expect(one, same);
      expect(one.hashCode, same.hashCode);
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
        wallhavenQueryParameters(
          filtered.withColor(null),
        ).containsKey('colors'),
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
        tags: <SearchTag>[SearchTag('nature')],
        page: 3,
        seed: 'abc123',
      );

      final SearchQuery colored = query.withColor(WallpaperColor('#ea4c88'));

      expect(colored.withColor(null), query);
      expect(colored.term, 'sunset');
      expect(colored.sorting, Sorting.toplist);
      expect(colored.tags, query.tags);
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
