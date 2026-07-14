import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

void main() {
  group('applyTo', () {
    test('applies the two fields the account is allowed to set', () {
      final SearchQuery query = _account.applyTo(const SearchQuery());

      expect(query.categories.toApiBits(), '010');
      expect(query.topRange, TopRange.oneWeek);
    });

    test('never touches the purity — browse always opens on safe, whatever '
        'the account browses on', () {
      final SearchQuery query = _account.applyTo(const SearchQuery());

      expect(query.purity.toApiBits(), '100');
    });

    test('leaves a purity the user chose for this session alone', () {
      // Turning Explicit on in the filter sheet must survive an account sync;
      // the account seeds a *fresh* query, it does not police an open one.
      const SearchQuery browsing = SearchQuery(
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.nsfw}),
      );

      expect(_account.applyTo(browsing).purity.toApiBits(), '101');
    });

    test('leaves everything the account has no business setting', () {
      final WallpaperColor blue = WallpaperColor('#0066cc');
      final SearchQuery browsing = SearchQuery(
        term: 'sunset',
        sorting: Sorting.hot,
        atLeast: const Resolution(1440, 3120),
        ratios: const <String>['16x9'],
        color: blue,
        page: 3,
        seed: 'abc',
      );

      final SearchQuery query = _account.applyTo(browsing);

      expect(query.term, 'sunset');
      expect(query.sorting, Sorting.hot);
      expect(query.atLeast, const Resolution(1440, 3120));
      // Ratios and resolutions are the two fields the account has and tela
      // refuses to sync — a desktop's 16x9 is not a phone's problem.
      expect(query.ratios, <String>['16x9']);
      expect(query.color, blue);
      expect(query.page, 3);
      expect(query.seed, 'abc');
    });
  });

  group('tryParse', () {
    test('reads back what the repository writes', () {
      final AccountSettings? parsed = AccountSettings.tryParse(
        storedCategories: _account.categories.toApiBits(),
        storedTopRange: _account.topRange.apiValue,
      );

      expect(parsed, _account);
    });

    test('answers null for a corrupt row of either', () {
      expect(_parse(categories: '11'), isNull);
      expect(_parse(categories: '000'), isNull);
      expect(_parse(categories: '1x0'), isNull);
      expect(_parse(topRange: '1m'), isNull);
      expect(_parse(topRange: ''), isNull);
    });
  });

  group('equality', () {
    test('compares the categories by members, not by set identity', () {
      const AccountSettings one = AccountSettings(
        categories: CategoryFilter(<Category>{Category.anime, Category.people}),
        topRange: TopRange.oneWeek,
      );
      const AccountSettings same = AccountSettings(
        categories: CategoryFilter(<Category>{Category.people, Category.anime}),
        topRange: TopRange.oneWeek,
      );

      expect(one, same);
      expect(one.hashCode, same.hashCode);
    });

    test('notices each field changing', () {
      expect(
        _account,
        isNot(
          AccountSettings(
            categories: CategoryFilter.all,
            topRange: _account.topRange,
          ),
        ),
      );
      expect(
        _account,
        isNot(
          AccountSettings(
            categories: _account.categories,
            topRange: TopRange.oneYear,
          ),
        ),
      );
    });
  });
}

const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);

AccountSettings? _parse({String categories = '111', String topRange = '1M'}) {
  return AccountSettings.tryParse(
    storedCategories: categories,
    storedTopRange: topRange,
  );
}
