import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/account_defaults.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/browse_query_controller.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';

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

    test("opens on the account's defaults once they are synced", () async {
      final ProviderContainer container = _container(account: _account);
      await container.read(accountDefaultsProvider.future);

      final SearchQuery query = container.read(browseQueryProvider);

      expect(query.categories.toApiBits(), '010');
      expect(query.topRange, TopRange.oneWeek);
      // The account has no say over the rest of the query — least of all the
      // purity, which always opens on safe.
      expect(query.purity.toApiBits(), '100');
      expect(query.ratios, <String>['9x16']);
    });

    test('adopting the account leaves the search term alone — searching is '
        'not an opinion about categories', () async {
      final ProviderContainer container = _container(account: _account);
      container.read(browseQueryProvider.notifier).search('sunset');

      await container.read(accountDefaultsProvider.future);

      final SearchQuery query = container.read(browseQueryProvider);
      expect(query.term, 'sunset');
      expect(query.categories.toApiBits(), '010');
    });

    test('never overrides a filter the user set by hand', () async {
      final ProviderContainer container = _container(account: _account);
      container
          .read(browseQueryProvider.notifier)
          .applyFilters(
            const SearchQuery(
              categories: CategoryFilter(<Category>{
                Category.people,
              }),
            ),
          );

      await container.read(accountDefaultsProvider.future);

      // The sync landed underneath, but the choice on screen is the user's.
      expect(
        container.read(browseQueryProvider).categories.toApiBits(),
        '001',
      );
    });

    test(
      "resetting the filters returns to the account's, not tela's",
      () async {
        final ProviderContainer container = _container(account: _account);
        await container.read(accountDefaultsProvider.future);

        container.read(browseQueryProvider.notifier)
          ..applyFilters(
            const SearchQuery(
              categories: CategoryFilter(<Category>{
                Category.people,
              }),
            ),
          )
          ..clearFilters();

        expect(
          container.read(browseQueryProvider).categories.toApiBits(),
          '010',
        );
      },
    );

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

/// An account whose every field differs from tela's own defaults, so adopting
/// it cannot pass by accidentally reading a default back.
const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);

/// A container whose Wallhaven account has [account] as its browse defaults, or
/// no key at all when it is null.
ProviderContainer _container({AccountSettings? account}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(
        FakeSettingsRepository(accountDefaults: account),
      ),
      secretStoreProvider.overrideWithValue(
        FakeSecretStore(storedKey: account == null ? null : 'abc123'),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
