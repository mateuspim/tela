import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/use_cases/load_account_defaults.dart';
import 'package:tela/domain/use_cases/sync_account_defaults.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_settings_repository.dart';
import '../../fakes/fake_wallhaven_api.dart';

void main() {
  test('answers null when no key was ever saved', () {
    expect(_load().call(), completion(isNull));
  });

  test('hands back the stored defaults while a key is stored', () {
    final LoadAccountDefaults load = _load(
      stored: _account,
      storedKey: 'abc123',
    );

    expect(load(), completion(_account));
  });

  test('the defaults it hands back cannot carry a purity at all, so browse '
      'opens on safe no matter what the account browses on', () async {
    final LoadAccountDefaults load = _load(
      stored: _account,
      storedKey: 'abc123',
    );

    final AccountSettings? defaults = await load();

    expect(defaults?.applyTo(const SearchQuery()).purity.toApiBits(), '100');
  });

  group('backfill', () {
    test('syncs a key that predates the sync — the upgrade case, where the '
        'feature would otherwise never run', () async {
      final FakeWallhavenApi api = FakeWallhavenApi(account: _account);
      final FakeSettingsRepository settings = FakeSettingsRepository();
      final LoadAccountDefaults load = _load(
        api: api,
        settings: settings,
        storedKey: 'abc123',
      );

      expect(await load(), _account);
      expect(api.accountSettingsCalls, 1);
      // Written, so the next load costs nothing.
      expect(settings.accountSaved, _account);
    });

    test('costs nothing once the defaults are there', () async {
      final FakeWallhavenApi api = FakeWallhavenApi();
      final LoadAccountDefaults load = _load(
        api: api,
        stored: _account,
        storedKey: 'abc123',
      );

      await load();

      expect(api.accountSettingsCalls, isZero);
    });

    test(
      'never spends a request without a key — Wallhaven would 401',
      () async {
        final FakeWallhavenApi api = FakeWallhavenApi();
        final LoadAccountDefaults load = _load(api: api);

        await load();

        expect(api.accountSettingsCalls, isZero);
      },
    );

    test('an unreachable account costs the defaults, not the app', () async {
      final LoadAccountDefaults load = _load(
        api: FakeWallhavenApi(failure: const NetworkFailure()),
        storedKey: 'abc123',
      );

      expect(await load(), isNull);
    });

    test('a rejected key costs the defaults and nothing else — forgetting the '
        "key is the user's call, not a failed sync's", () async {
      final FakeSecretStore secrets = FakeSecretStore(storedKey: 'stale');
      final LoadAccountDefaults load = LoadAccountDefaults(
        settings: FakeSettingsRepository(),
        secrets: secrets,
        syncDefaults: SyncAccountDefaults(
          api: FakeWallhavenApi(failure: const InvalidApiKeyFailure()),
          settings: FakeSettingsRepository(),
        ),
      );

      expect(await load(), isNull);
      expect(secrets.storedKey, 'stale');
    });
  });
}

/// An account that browses anime and tops by the week — every field it has is
/// distinguishable from tela's own defaults.
const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);

LoadAccountDefaults _load({
  AccountSettings? stored,
  String? storedKey,
  FakeWallhavenApi? api,
  FakeSettingsRepository? settings,
}) {
  final FakeSettingsRepository store =
      settings ?? FakeSettingsRepository(accountDefaults: stored);
  return LoadAccountDefaults(
    settings: store,
    secrets: FakeSecretStore(storedKey: storedKey),
    syncDefaults: SyncAccountDefaults(
      api: api ?? FakeWallhavenApi(),
      settings: store,
    ),
  );
}
