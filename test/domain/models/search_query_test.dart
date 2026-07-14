import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';

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
          atLeast: Resolution(1080, 2400),
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
