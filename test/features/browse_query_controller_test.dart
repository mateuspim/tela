import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/browse_defaults.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
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
      expect(query.ratios, <RatioChoice>[const ExactRatio(9, 16)]);
      expect(query.term, isEmpty);
    });

    test("opens on the account's defaults once they are synced", () async {
      final ProviderContainer container = _container(account: _account);
      await container.read(browseDefaultsProvider.future);

      final SearchQuery query = container.read(browseQueryProvider);

      expect(query.categories.toApiBits(), '010');
      expect(query.topRange, TopRange.oneWeek);
      // The account has no say over the rest of the query — least of all the
      // purity, which always opens on safe.
      expect(query.purity.toApiBits(), '100');
      expect(query.ratios, <RatioChoice>[const ExactRatio(9, 16)]);
    });

    test('adopting the account leaves the search term alone — searching is '
        'not an opinion about categories', () async {
      final ProviderContainer container = _container(account: _account);
      container.read(browseQueryProvider.notifier).search('sunset');

      await container.read(browseDefaultsProvider.future);

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

      await container.read(browseDefaultsProvider.future);

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
        await container.read(browseDefaultsProvider.future);

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

    test("opens on the device's snapshot when that is the source", () async {
      final ProviderContainer container = _container(
        source: BrowseDefaultsSource.device,
        account: _account,
        device: _device,
      );
      await container.read(browseDefaultsProvider.future);

      final SearchQuery query = container.read(browseQueryProvider);

      expect(query.categories.toApiBits(), '001');
      expect(query.topRange, TopRange.oneYear);
      expect(query.ratios, <RatioChoice>[const ExactRatio(16, 9)]);
      expect(query.order, SortOrder.asc);
      // A saved snapshot cannot carry a purity either. Browse still opens safe.
      expect(query.purity.toApiBits(), '100');
    });

    test(
      'switching the source overrules a filter set by hand — a switch you '
      'just flipped in Settings is not something the old listing outranks',
      () async {
        final ProviderContainer container = _container(
          account: _account,
          device: _device,
        );
        await container.read(browseDefaultsProvider.future);
        container
            .read(browseQueryProvider.notifier)
            .applyFilters(
              const SearchQuery(
                categories: CategoryFilter(<Category>{Category.general}),
              ),
            );

        await container
            .read(browseDefaultsProvider.notifier)
            .useSource(BrowseDefaultsSource.device);
        await container.read(browseDefaultsProvider.future);

        // Unlike a *sync* landing underneath, which must not.
        expect(
          container.read(browseQueryProvider).categories.toApiBits(),
          '001',
        );
      },
    );

    test(
      'adopting a snapshot leaves a purity chosen for this session alone',
      () async {
        final ProviderContainer container = _container(
          account: _account,
          device: _device,
        );
        await container.read(browseDefaultsProvider.future);
        container
            .read(browseQueryProvider.notifier)
            .applyFilters(
              const SearchQuery(
                purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
              ),
            );

        await container
            .read(browseDefaultsProvider.notifier)
            .useSource(BrowseDefaultsSource.device);
        await container.read(browseDefaultsProvider.future);

        // The snapshot carries no purity, so it must not switch the grid back
        // to safe under someone who turned sketchy on a moment ago.
        final SearchQuery query = container.read(browseQueryProvider);
        expect(query.purity.toApiBits(), '110');
        expect(query.categories.toApiBits(), '001');
      },
    );

    test(
      'saving the current filters keeps them, and switches the source',
      () async {
        final ProviderContainer container = _container(account: _account);
        await container.read(browseDefaultsProvider.future);

        await container
            .read(browseDefaultsProvider.notifier)
            .saveDeviceDefaults(
              const SearchQuery(
                categories: CategoryFilter(<Category>{Category.general}),
                topRange: TopRange.oneDay,
              ),
            );
        await container.read(browseDefaultsProvider.future);

        final SearchQuery query = container.read(browseQueryProvider);
        expect(query.categories.toApiBits(), '100');
        expect(query.topRange, TopRange.oneDay);
        // Saving without switching would be a button that does nothing.
        expect(
          container.read(browseDefaultsProvider).value?.source,
          BrowseDefaultsSource.device,
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

  group('offerableSortings', () {
    test('withholds relevance until there is a term to rank against', () {
      expect(
        offerableSortings(hasTerm: false),
        isNot(contains(Sorting.relevance)),
      );
      expect(offerableSortings(hasTerm: true), contains(Sorting.relevance));
    });

    test('leads with relevance, so a search lands on it', () {
      expect(offerableSortings(hasTerm: true).first, Sorting.relevance);
    });

    test('offers every sorting Wallhaven has, and no more', () {
      // The gap this slice closes: views and favorites existed in the enum from
      // Wave 1 and could not be reached at all, because the tab *was* the
      // sorting and there were four tabs.
      expect(
        offerableSortings(hasTerm: true).toSet(),
        Sorting.values.toSet(),
        reason: 'a sorting nothing offers is a listing nobody can reach',
      );
    });

    test('a termless listing keeps the six that stand on their own', () {
      expect(offerableSortings(hasTerm: false), <Sorting>[
        Sorting.dateAdded,
        Sorting.toplist,
        Sorting.hot,
        Sorting.random,
        Sorting.views,
        Sorting.favorites,
      ]);
    });
  });
}

/// An account whose every field differs from tela's own defaults, so adopting
/// it cannot pass by accidentally reading a default back.
const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);

/// A snapshot whose every field differs from both tela's defaults and
/// [_account]'s, so adopting one cannot be mistaken for the other.
const BrowseDefaults _device = BrowseDefaults(
  categories: CategoryFilter(<Category>{Category.people}),
  topRange: TopRange.oneYear,
  ratios: <RatioChoice>[ExactRatio(16, 9)],
  order: SortOrder.asc,
);

/// A container whose Wallhaven account has [account] as its browse defaults, or
/// no key at all when it is null.
ProviderContainer _container({
  AccountSettings? account,
  BrowseDefaults? device,
  BrowseDefaultsSource source = BrowseDefaultsSource.account,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(
        FakeSettingsRepository(
          accountDefaults: account,
          deviceDefaults: device,
          source: source,
        ),
      ),
      secretStoreProvider.overrideWithValue(
        FakeSecretStore(storedKey: account == null ? null : 'abc123'),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
