import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/use_cases/load_account_defaults.dart';
import 'package:tela/domain/use_cases/resolve_browse_defaults.dart';
import 'package:tela/domain/use_cases/sync_account_defaults.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_settings_repository.dart';
import '../../fakes/fake_wallpaper_source.dart';

void main() {
  test('takes the account when that is the source', () async {
    final ResolveBrowseDefaults resolve = _resolve(
      account: _account,
      device: _device,
    );

    final ActiveBrowseDefaults active = await resolve();

    expect(active.source, BrowseDefaultsSource.account);
    expect(active.defaults, _account.toBrowseDefaults());
  });

  test('takes the device snapshot when that is the source', () async {
    final ResolveBrowseDefaults resolve = _resolve(
      source: BrowseDefaultsSource.device,
      account: _account,
      device: _device,
    );

    final ActiveBrowseDefaults active = await resolve();

    expect(active.source, BrowseDefaultsSource.device);
    expect(active.defaults, _device);
  });

  test("a source with nothing stored falls back to tela's own, which is not "
      'an error — picking a source is a preference, not a promise that it '
      'has an answer', () async {
    final ResolveBrowseDefaults noAccount = _resolve();
    final ResolveBrowseDefaults noSnapshot = _resolve(
      source: BrowseDefaultsSource.device,
      account: _account,
    );

    expect((await noAccount()).defaults, const BrowseDefaults());
    expect((await noSnapshot()).defaults, const BrowseDefaults());
  });

  test('the account never opens browse on explicit', () async {
    // An account carries no purity, so a fresh query keeps tela's own safe.
    final ResolveBrowseDefaults resolve = _resolve(
      account: _account,
      apiKey: 'key',
    );

    final SearchQuery query = (await resolve()).defaults.applyTo(
      const SearchQuery(),
    );

    expect(query.purity.purities, <Purity>{Purity.sfw});
  });

  test('a saved purity opens browse when a key unlocks it', () async {
    final ResolveBrowseDefaults resolve = _resolve(
      source: BrowseDefaultsSource.device,
      device: _everyPurity,
      apiKey: 'key',
    );

    expect((await resolve()).defaults.purity, _allPurities);
  });

  test('a saved explicit purity is stripped without a key', () async {
    // Regression guard for the save-purity change: a keyless Wallhaven would
    // refuse the very first request rather than open on what it can serve.
    final ResolveBrowseDefaults resolve = _resolve(
      source: BrowseDefaultsSource.device,
      device: _everyPurity,
    );

    expect((await resolve()).defaults.purity?.purities, <Purity>{
      Purity.sfw,
      Purity.sketchy,
    });
  });
}

const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);

const BrowseDefaults _device = BrowseDefaults(
  categories: CategoryFilter(<Category>{Category.people}),
  topRange: TopRange.oneYear,
  ratios: <RatioChoice>[ExactRatio(16, 9)],
  order: SortOrder.asc,
);

const PurityFilter _allPurities = PurityFilter(<Purity>{
  Purity.sfw,
  Purity.sketchy,
  Purity.nsfw,
});

const BrowseDefaults _everyPurity = BrowseDefaults(purity: _allPurities);

ResolveBrowseDefaults _resolve({
  BrowseDefaultsSource source = BrowseDefaultsSource.account,
  AccountSettings? account,
  BrowseDefaults? device,
  String? apiKey,
}) {
  final FakeSecretStore secrets = FakeSecretStore(storedKey: apiKey);
  final FakeSettingsRepository settings = FakeSettingsRepository(
    accountDefaults: account,
    source: source,
    deviceDefaults: device,
  );
  return ResolveBrowseDefaults(
    settings: settings,
    loadAccount: LoadAccountDefaults(
      settings: settings,
      secrets: secrets,
      syncDefaults: SyncAccountDefaults(
        source: FakeWallpaperSource(),
        settings: settings,
      ),
    ),
    secrets: secrets,
  );
}
