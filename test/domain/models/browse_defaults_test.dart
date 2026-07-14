import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

void main() {
  group('of', () {
    test('captures the filters a query expresses', () {
      final BrowseDefaults captured = BrowseDefaults.of(_browsing);

      expect(captured.categories.toApiBits(), '010');
      expect(captured.topRange, TopRange.oneWeek);
      expect(captured.ratios, <String>['16x9']);
      expect(captured.order, SortOrder.asc);
      expect(captured.color, WallpaperColor('#0066cc'));
    });

    test('never captures the purity, however the query is browsing', () {
      // The load-bearing one. A saved default carrying explicit would put a
      // grid of it on the launch screen, which is the bug the account sync
      // already shipped once (hardware, 2026-07-14) — the user's own
      // fingerprints on it would not make it a better front page.
      const SearchQuery explicit = SearchQuery(
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.nsfw}),
      );

      final SearchQuery reopened = BrowseDefaults.of(
        explicit,
      ).applyTo(const SearchQuery());

      expect(reopened.purity.toApiBits(), '100');
    });

    test('never captures the term — searching is not a filter', () {
      const SearchQuery searching = SearchQuery(term: 'sunset');

      final SearchQuery reopened = BrowseDefaults.of(
        searching,
      ).applyTo(const SearchQuery());

      expect(reopened.term, isEmpty);
    });
  });

  group('applyTo', () {
    test('sets the five fields it speaks for', () {
      final SearchQuery query = BrowseDefaults.of(
        _browsing,
      ).applyTo(const SearchQuery());

      expect(query.categories.toApiBits(), '010');
      expect(query.topRange, TopRange.oneWeek);
      expect(query.ratios, <String>['16x9']);
      expect(query.order, SortOrder.asc);
      expect(query.color, WallpaperColor('#0066cc'));
    });

    test('leaves everything it does not speak for exactly as it was', () {
      const SearchQuery browsing = SearchQuery(
        term: 'sunset',
        sorting: Sorting.hot,
        purity: PurityFilter(<Purity>{Purity.sketchy}),
        atLeast: Resolution(1440, 3120),
        page: 3,
        seed: 'abc',
      );

      final SearchQuery query = const BrowseDefaults().applyTo(browsing);

      expect(query.term, 'sunset');
      expect(query.sorting, Sorting.hot);
      // Adopting a default must not switch the grid back to safe under someone
      // who turned sketchy on for this session.
      expect(query.purity.toApiBits(), '010');
      expect(query.atLeast, const Resolution(1440, 3120));
      expect(query.page, 3);
      expect(query.seed, 'abc');
    });

    test('clears a colour the defaults do not carry', () {
      // `copyWith` structurally cannot do this — it reads a null colour as
      // "leave it alone" — so an adopted default would be unable to turn the
      // swatch off. Hence `withColor`.
      final SearchQuery filtered = const SearchQuery().withColor(
        WallpaperColor('#0066cc'),
      );

      expect(const BrowseDefaults().applyTo(filtered).color, isNull);
    });
  });

  group('tryParse', () {
    test('reads back what the repository writes', () {
      final BrowseDefaults saved = BrowseDefaults.of(_browsing);

      final BrowseDefaults? parsed = BrowseDefaults.tryParse(
        storedCategories: saved.categories.toApiBits(),
        storedTopRange: saved.topRange.apiValue,
        storedRatios: saved.encodedRatios(),
        storedOrder: saved.order.name,
        storedColor: saved.color?.hex,
      );

      expect(parsed, saved);
    });

    test('an empty ratio list is "any shape", not a missing one', () {
      final BrowseDefaults? parsed = _parse(ratios: '');

      expect(parsed?.ratios, isEmpty);
    });

    test('an absent colour row is "any colour"', () {
      expect(_parse()?.color, isNull);
    });

    test('one unreadable swatch costs the colour, not the snapshot', () {
      final BrowseDefaults? parsed = _parse(color: 'chartreuse');

      expect(parsed, isNotNull);
      expect(parsed?.color, isNull);
    });

    test('answers null for a corrupt row of anything required', () {
      expect(_parse(categories: '000'), isNull);
      expect(_parse(categories: '1x0'), isNull);
      expect(_parse(topRange: '1m'), isNull);
      expect(_parse(order: 'sideways'), isNull);
    });
  });

  group('equality', () {
    test('compares the ratios element-wise, not by list identity', () {
      // Deliberately not const: two const snapshots would be canonicalized to
      // the *same object*, and identity would pass a test about equality.
      final BrowseDefaults one = BrowseDefaults(
        ratios: List<String>.of(<String>['9x16']),
      );
      final BrowseDefaults same = BrowseDefaults(
        ratios: List<String>.of(<String>['9x16']),
      );

      expect(one, same);
      expect(one.hashCode, same.hashCode);
    });

    test('a changed field is a changed snapshot', () {
      const BrowseDefaults base = BrowseDefaults();

      expect(base, isNot(const BrowseDefaults(topRange: TopRange.oneYear)));
      expect(base, isNot(const BrowseDefaults(order: SortOrder.asc)));
      expect(base, isNot(const BrowseDefaults(ratios: <String>[])));
      expect(base, isNot(base.applyToColor(WallpaperColor('#0066cc'))));
    });
  });

  group('BrowseDefaultsSource', () {
    test('reads its stored name back', () {
      expect(
        BrowseDefaultsSource.tryFromName('device'),
        BrowseDefaultsSource.device,
      );
      expect(
        BrowseDefaultsSource.tryFromName('account'),
        BrowseDefaultsSource.account,
      );
    });

    test('answers null for a name no build ever wrote', () {
      expect(BrowseDefaultsSource.tryFromName('cloud'), isNull);
      expect(BrowseDefaultsSource.tryFromName(''), isNull);
    });
  });
}

/// A query whose every filter differs from tela's own defaults, so capturing it
/// cannot pass by accidentally reading a default back.
final SearchQuery _browsing = SearchQuery(
  categories: const CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
  ratios: const <String>['16x9'],
  order: SortOrder.asc,
  color: WallpaperColor('#0066cc'),
);

BrowseDefaults? _parse({
  String categories = '111',
  String topRange = '1M',
  String ratios = '9x16',
  String order = 'desc',
  String? color,
}) {
  return BrowseDefaults.tryParse(
    storedCategories: categories,
    storedTopRange: topRange,
    storedRatios: ratios,
    storedOrder: order,
    storedColor: color,
  );
}

/// A snapshot differing from this one only by its colour.
extension on BrowseDefaults {
  BrowseDefaults applyToColor(WallpaperColor color) {
    return BrowseDefaults(
      categories: categories,
      topRange: topRange,
      ratios: ratios,
      order: order,
      color: color,
    );
  }
}
