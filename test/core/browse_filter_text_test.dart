import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/browse_filter_text.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/resolution_filter.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';

void main() {
  group('activeBrowseFilterCount', () {
    test('the opening browse query needs no badge', () {
      expect(activeBrowseFilterCount(const SearchQuery()), 0);
    });

    test('counts changed groups rather than individual choices', () {
      const SearchQuery query = SearchQuery(
        categories: CategoryFilter(<Category>{Category.anime}),
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
        tags: <SearchTag>[SearchTag('nature'), SearchTag('sky')],
        resolution: AtLeastResolution(Resolution(1920, 1080)),
      );

      expect(activeBrowseFilterCount(query), 4);
    });

    test('does not count a search term or sorting tab as a filter', () {
      const SearchQuery query = SearchQuery(
        term: 'sunset',
        sorting: Sorting.relevance,
      );

      expect(activeBrowseFilterCount(query), 0);
    });
  });
}
