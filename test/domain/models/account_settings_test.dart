import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

void main() {
  group('applyTo', () {
    test('applies the three fields the account is allowed to set', () {
      final SearchQuery query = _account.applyTo(const SearchQuery());

      expect(query.categories.toApiBits(), '010');
      expect(query.purity.toApiBits(), '110');
      expect(query.topRange, TopRange.oneWeek);
    });

    test('never seeds explicit, even from an account that browses it', () {
      const AccountSettings explicit = AccountSettings(
        categories: CategoryFilter.all,
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy, Purity.nsfw}),
        topRange: TopRange.oneMonth,
      );

      final SearchQuery query = explicit.applyTo(const SearchQuery());

      // Sketchy seeds — it needs no key and it is not explicit. Explicit is a
      // thing you turn on in the filter sheet, per session.
      expect(query.purity.toApiBits(), '110');
    });

    test('an explicit-only account seeds safe, not the "000" mask', () {
      const AccountSettings explicit = AccountSettings(
        categories: CategoryFilter.all,
        purity: PurityFilter(<Purity>{Purity.nsfw}),
        topRange: TopRange.oneMonth,
      );

      expect(explicit.applyTo(const SearchQuery()).purity.toApiBits(), '100');
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

  group('browsablePurity', () {
    test("keeps the account's explicit purity as the account stated it", () {
      // The *stored* account is the account's truth; only what browse opens on
      // is narrowed. A future "browse explicit" affordance needs this row.
      const AccountSettings explicit = AccountSettings(
        categories: CategoryFilter.all,
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.nsfw}),
        topRange: TopRange.oneMonth,
      );

      expect(explicit.purity.toApiBits(), '101');
      expect(explicit.browsablePurity.toApiBits(), '100');
    });

    test('leaves a safe account alone', () {
      expect(_account.browsablePurity.toApiBits(), '110');
    });
  });

  group('tryParse', () {
    test('reads back what the repository writes', () {
      final AccountSettings? parsed = AccountSettings.tryParse(
        storedCategories: _account.categories.toApiBits(),
        storedPurity: _account.purity.toApiBits(),
        storedTopRange: _account.topRange.apiValue,
      );

      expect(parsed, _account);
    });

    test('answers null for a corrupt row of any of the three', () {
      expect(_parse(categories: '11'), isNull);
      expect(_parse(categories: '000'), isNull);
      expect(_parse(purity: 'sfw'), isNull);
      expect(_parse(purity: '1x0'), isNull);
      expect(_parse(topRange: '1m'), isNull);
      expect(_parse(topRange: ''), isNull);
    });
  });

  group('equality', () {
    test('compares the filters by members, not by set identity', () {
      const AccountSettings one = AccountSettings(
        categories: CategoryFilter(<Category>{Category.anime, Category.people}),
        purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
        topRange: TopRange.oneWeek,
      );
      const AccountSettings same = AccountSettings(
        categories: CategoryFilter(<Category>{Category.people, Category.anime}),
        purity: PurityFilter(<Purity>{Purity.sketchy, Purity.sfw}),
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
            purity: _account.purity,
            topRange: _account.topRange,
          ),
        ),
      );
      expect(
        _account,
        isNot(
          AccountSettings(
            categories: _account.categories,
            purity: PurityFilter.sfwOnly,
            topRange: _account.topRange,
          ),
        ),
      );
      expect(
        _account,
        isNot(
          AccountSettings(
            categories: _account.categories,
            purity: _account.purity,
            topRange: TopRange.oneYear,
          ),
        ),
      );
    });
  });
}

const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
  topRange: TopRange.oneWeek,
);

AccountSettings? _parse({
  String categories = '111',
  String purity = '100',
  String topRange = '1M',
}) {
  return AccountSettings.tryParse(
    storedCategories: categories,
    storedPurity: purity,
    storedTopRange: topRange,
  );
}
