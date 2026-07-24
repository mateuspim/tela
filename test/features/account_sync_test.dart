import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/browse_defaults.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/settings/api_key_controller.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// The slice end to end: settings saves a key, and browse follows it.
///
/// The two features never import each other — they meet at
/// [browseDefaultsProvider] — so this is the only place the whole path is
/// visible at once.
void main() {
  test('saving a key adopts the account it belongs to', () async {
    final ProviderContainer container = _container(account: _explicitAccount);
    expect(
      container.read(browseQueryProvider).categories.encodeStored(),
      '111',
    );

    await container.read(apiKeyProvider.notifier).save('abc123');
    await container.read(browseDefaultsProvider.future);

    final SearchQuery query = container.read(browseQueryProvider);
    expect(query.categories.encodeStored(), '010');
    expect(query.topRange, TopRange.oneWeek);
    // The account browses explicit. The front page still opens on safe: sketchy
    // and explicit are per-session choices in the filter sheet, and no account
    // gets to make them for you.
    expect(query.purity.purities, <Purity>{Purity.sfw});
  });

  test('forgetting the key takes the account back out of browse', () async {
    final ProviderContainer container = _container(account: _explicitAccount);
    await container.read(apiKeyProvider.notifier).save('abc123');
    await container.read(browseDefaultsProvider.future);

    await container.read(apiKeyProvider.notifier).forget();
    await container.read(browseDefaultsProvider.future);

    // Back to tela's own: the defaults belong to an account this device can no
    // longer reach.
    final SearchQuery query = container.read(browseQueryProvider);
    expect(query.categories.encodeStored(), '111');
    expect(query.topRange, TopRange.oneMonth);
  });

  test('a key the user is still typing over does not change browse', () async {
    final ProviderContainer container = _container(account: _explicitAccount);
    container
        .read(browseQueryProvider.notifier)
        .applyFilters(
          const SearchQuery(
            categories: CategoryFilter(<Category>{Category.people}),
          ),
        );

    await container.read(apiKeyProvider.notifier).save('abc123');
    await container.read(browseDefaultsProvider.future);

    // The account seeds the defaults; it does not overrule a live choice.
    expect(
      container.read(browseQueryProvider).categories.encodeStored(),
      '001',
    );
  });
}

/// An account that browses anime and allows everything — every field different
/// from tela's own defaults.
const AccountSettings _explicitAccount = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);

ProviderContainer _container({required AccountSettings account}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      wallhavenSourceProvider.overrideWithValue(
        FakeWallpaperSource(account: account),
      ),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
