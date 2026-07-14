import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/browse_query_controller.dart';

void main() {
  group('BrowseQueryController', () {
    test('opens on the browse defaults: safe, every category, portrait', () {
      final ProviderContainer container = _container();

      final SearchQuery query = container.read(browseQueryProvider);

      expect(query.purity.toApiBits(), '100');
      expect(query.categories.toApiBits(), '111');
      expect(query.ratios, <String>['9x16']);
      expect(query.term, isEmpty);
    });

    test('trims the search term', () {
      final ProviderContainer container = _container();

      container.read(browseQueryProvider.notifier).search('  sunset  ');

      expect(container.read(browseQueryProvider).term, 'sunset');
    });

    test('keeps the term when filters are applied', () {
      final ProviderContainer container = _container();
      container.read(browseQueryProvider.notifier)
        ..search('sunset')
        ..applyFilters(const SearchQuery(purity: PurityFilter({Purity.nsfw})));

      final SearchQuery query = container.read(browseQueryProvider);
      expect(query.term, 'sunset');
      expect(query.purity.toApiBits(), '001');
    });

    test('resetting the filters leaves the term alone', () {
      final ProviderContainer container = _container();
      container.read(browseQueryProvider.notifier)
        ..search('sunset')
        ..applyFilters(
          const SearchQuery(categories: CategoryFilter({Category.anime})),
        )
        ..clearFilters();

      final SearchQuery query = container.read(browseQueryProvider);
      expect(query.term, 'sunset');
      expect(query.categories.toApiBits(), '111');
    });
  });

  group('toggledChoice', () {
    test('adds an unselected value and removes a selected one', () {
      expect(
        toggledChoice(<Purity>{Purity.sfw}, Purity.sketchy),
        <Purity>{Purity.sfw, Purity.sketchy},
      );
      expect(
        toggledChoice(<Purity>{Purity.sfw, Purity.sketchy}, Purity.sketchy),
        <Purity>{Purity.sfw},
      );
    });

    test('refuses to deselect the last one — an empty mask is a 400', () {
      expect(
        toggledChoice(<Purity>{Purity.sfw}, Purity.sfw),
        <Purity>{Purity.sfw},
      );
    });
  });

  group('offerablePurities', () {
    test('withholds nsfw until a key is stored', () {
      expect(offerablePurities(hasApiKey: false), <Purity>[
        Purity.sfw,
        Purity.sketchy,
      ]);
      expect(offerablePurities(hasApiKey: true), Purity.values);
    });
  });

  group('RatioChoice', () {
    test('reads the choice back out of a query', () {
      expect(RatioChoice.of(const SearchQuery()), RatioChoice.portrait);
      expect(
        RatioChoice.of(const SearchQuery(ratios: <String>['16x9'])),
        RatioChoice.landscape,
      );
      expect(
        RatioChoice.of(const SearchQuery(ratios: <String>[])),
        RatioChoice.any,
      );
    });

    test('falls back to any for a ratio set nothing offers', () {
      expect(
        RatioChoice.of(const SearchQuery(ratios: <String>['21x9'])),
        RatioChoice.any,
      );
    });
  });
}

ProviderContainer _container() {
  final ProviderContainer container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}
