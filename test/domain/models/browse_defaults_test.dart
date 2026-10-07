import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

void main() {
  group('of', () {
    test('captures the filters a query expresses', () {
      final BrowseDefaults captured = BrowseDefaults.of(_browsing);

      expect(captured.categories.encodeStored(), '010');
      expect(captured.topRange, TopRange.oneWeek);
      expect(captured.ratios, <RatioChoice>[const ExactRatio(16, 9)]);
      expect(captured.order, SortOrder.asc);
      expect(captured.color, WallpaperColor('#0066cc'));
    });

    test('captures the purity, which "Save as default" asked it to', () {
      // Regression (2026-10-07): a saved safe+sketchy+explicit reopened on
      // safe alone. Whether explicit may *stand* is ResolveBrowseDefaults'
      // call, made against the key — not a refusal to save it.
      const SearchQuery explicit = SearchQuery(
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.nsfw}),
      );

      final SearchQuery reopened = BrowseDefaults.of(
        explicit,
      ).applyTo(const SearchQuery());

      expect(reopened.purity.purities, <Purity>{Purity.sfw, Purity.nsfw});
    });

    test('never captures the term — searching is not a filter', () {
      const SearchQuery searching = SearchQuery(term: 'sunset');

      final SearchQuery reopened = BrowseDefaults.of(
        searching,
      ).applyTo(const SearchQuery());

      expect(reopened.term, isEmpty);
    });
  });

  group('isExpressedBy', () {
    test('a query on the defaults expresses them, whatever its purity', () {
      // Defaults with no purity have no opinion on it, so a sketchy session
      // still counts as untouched — what lets a late account sync land.
      const SearchQuery sketchy = SearchQuery(
        purity: PurityFilter(<Purity>{Purity.sketchy}),
      );

      expect(const BrowseDefaults().isExpressedBy(sketchy), isTrue);
    });

    test('a query that moved a filter, or a saved purity, does not', () {
      const BrowseDefaults saved = BrowseDefaults(
        purity: PurityFilter(<Purity>{Purity.sketchy}),
      );

      expect(saved.isExpressedBy(const SearchQuery()), isFalse);
      expect(
        const BrowseDefaults().isExpressedBy(
          const SearchQuery(topRange: TopRange.oneYear),
        ),
        isFalse,
      );
    });
  });

  group('withoutNsfw', () {
    test('takes explicit out of a saved purity and nothing else', () {
      const BrowseDefaults saved = BrowseDefaults(
        topRange: TopRange.oneYear,
        purity: PurityFilter(<Purity>{Purity.sketchy, Purity.nsfw}),
      );

      expect(
        saved.withoutNsfw(),
        const BrowseDefaults(
          topRange: TopRange.oneYear,
          purity: PurityFilter(<Purity>{Purity.sketchy}),
        ),
      );
    });

    test('leaves "no opinion" alone', () {
      expect(const BrowseDefaults().withoutNsfw().purity, isNull);
    });
  });

  group('applyTo', () {
    test('sets the five fields it speaks for', () {
      final SearchQuery query = BrowseDefaults.of(
        _browsing,
      ).applyTo(const SearchQuery());

      expect(query.categories.encodeStored(), '010');
      expect(query.topRange, TopRange.oneWeek);
      expect(query.ratios, <RatioChoice>[const ExactRatio(16, 9)]);
      expect(query.order, SortOrder.asc);
      expect(query.color, WallpaperColor('#0066cc'));
    });

    test('leaves everything it does not speak for exactly as it was', () {
      const SearchQuery browsing = SearchQuery(
        term: 'sunset',
        sorting: Sorting.hot,
        purity: PurityFilter(<Purity>{Purity.sketchy}),
        page: 3,
        seed: 'abc',
      );

      final SearchQuery query = const BrowseDefaults().applyTo(browsing);

      expect(query.term, 'sunset');
      expect(query.sorting, Sorting.hot);
      // Adopting a default must not switch the grid back to safe under someone
      // who turned sketchy on for this session.
      expect(query.purity.purities, <Purity>{Purity.sketchy});
      expect(query.page, 3);
      expect(query.seed, 'abc');
    });

    test('carries the resolution filter, which it once could not', () {
      // It used to be `atLeast`, imposed by the browse screen from the device's
      // own screen and choosable by nobody — so there was nothing to save. Now
      // that it is a filter the user sets, a snapshot has to carry it.
      final SearchQuery browsing = SearchQuery(
        resolution: ExactResolutions(const <Resolution>[
          Resolution(1920, 1080),
        ]),
      );

      final BrowseDefaults captured = BrowseDefaults.of(browsing);

      expect(
        captured.resolution,
        ExactResolutions(const <Resolution>[Resolution(1920, 1080)]),
      );
      expect(
        captured.applyTo(const SearchQuery()).resolution,
        ExactResolutions(const <Resolution>[Resolution(1920, 1080)]),
      );
    });

    test('an absent resolution row reads as Automatic', () {
      // Which is what every snapshot saved before this filter existed browsed
      // on, so a device that upgrades browses exactly as it did yesterday.
      final BrowseDefaults? parsed = _parse();

      expect(parsed?.resolution, const AutomaticResolution());
    });

    test('an unreadable resolution costs the filter, not the snapshot', () {
      final BrowseDefaults? parsed = _parse(resolution: 'exact:nonsense');

      expect(parsed, isNotNull);
      expect(parsed?.resolution, const AutomaticResolution());
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
        storedCategories: saved.categories.encodeStored(),
        storedTopRange: saved.topRange.apiValue,
        storedRatios: saved.encodedRatios(),
        storedOrder: saved.order.name,
        storedColor: saved.color?.hex,
        storedPurity: saved.encodedPurity(),
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

    test('an absent purity row is "no opinion", as every older snapshot', () {
      expect(_parse()?.purity, isNull);
    });

    test('an unreadable purity costs the purity, not the snapshot', () {
      final BrowseDefaults? parsed = _parse(purity: '000');

      expect(parsed, isNotNull);
      expect(parsed?.purity, isNull);
    });

    test('reads a stored purity mask back', () {
      expect(_parse(purity: '011')?.purity?.purities, <Purity>{
        Purity.sketchy,
        Purity.nsfw,
      });
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
        ratios: List<RatioChoice>.of(<RatioChoice>[const ExactRatio(9, 16)]),
      );
      final BrowseDefaults same = BrowseDefaults(
        ratios: List<RatioChoice>.of(<RatioChoice>[const ExactRatio(9, 16)]),
      );

      expect(one, same);
      expect(one.hashCode, same.hashCode);
    });

    test('a changed field is a changed snapshot', () {
      const BrowseDefaults base = BrowseDefaults();

      expect(base, isNot(const BrowseDefaults(topRange: TopRange.oneYear)));
      expect(base, isNot(const BrowseDefaults(order: SortOrder.asc)));
      expect(base, isNot(const BrowseDefaults(ratios: <RatioChoice>[])));
      expect(base, isNot(base.applyToColor(WallpaperColor('#0066cc'))));
      expect(base, isNot(const BrowseDefaults(purity: PurityFilter.sfwOnly)));
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
  ratios: const <RatioChoice>[ExactRatio(16, 9)],
  order: SortOrder.asc,
  color: WallpaperColor('#0066cc'),
);

BrowseDefaults? _parse({
  String categories = '111',
  String topRange = '1M',
  String ratios = '9x16',
  String order = 'desc',
  String? color,
  String? resolution,
  String? purity,
}) {
  return BrowseDefaults.tryParse(
    storedCategories: categories,
    storedTopRange: topRange,
    storedRatios: ratios,
    storedOrder: order,
    storedColor: color,
    storedResolution: resolution,
    storedPurity: purity,
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
