import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/search_query.dart';

void main() {
  group('toBrowseDefaults', () {
    test('carries the two fields the account is allowed to set', () {
      final BrowseDefaults defaults = _account.toBrowseDefaults();

      expect(defaults.categories.toApiBits(), '010');
      expect(defaults.topRange, TopRange.oneWeek);
    });

    test("keeps tela's own values for the three the account cannot set", () {
      final BrowseDefaults defaults = _account.toBrowseDefaults();

      // `resolutions` and `aspect_ratios` are set by desktop users at a
      // desktop: a synced 16x9 would fill a phone grid with landscape
      // wallpapers. The account has no colour at all.
      expect(defaults.ratios, const BrowseDefaults().ratios);
      expect(defaults.order, const BrowseDefaults().order);
      expect(defaults.color, isNull);
    });

    test('opens browse on safe, whatever the account browses on', () {
      // The whole reason purity is not a field: an account with NSFW enabled
      // made the launch screen a grid of explicit thumbnails (hardware,
      // 2026-07-14). There is nothing here for it to come back through.
      final SearchQuery query = _account.toBrowseDefaults().applyTo(
        const SearchQuery(),
      );

      expect(query.purity.toApiBits(), '100');
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
