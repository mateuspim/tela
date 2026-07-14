import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
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
      stored: _explicitAccount,
      storedKey: 'abc123',
    );

    expect(load(), completion(_explicitAccount));
  });

  test('strips explicit content when the key is gone — an nsfw default with '
      'no key is a 401, not a grid', () async {
    final LoadAccountDefaults load = _load(stored: _explicitAccount);

    final AccountSettings? defaults = await load();

    expect(defaults?.purity.toApiBits(), '110');
    // Everything that is not the purity survives the strip.
    expect(defaults?.categories.toApiBits(), '010');
    expect(defaults?.topRange, TopRange.oneWeek);
  });

  test('an explicit-only account with no key falls back to safe, not to an '
      'empty mask', () async {
    final LoadAccountDefaults load = _load(
      stored: const AccountSettings(
        categories: CategoryFilter.all,
        purity: PurityFilter(<Purity>{Purity.nsfw}),
        topRange: TopRange.oneMonth,
      ),
    );

    final AccountSettings? defaults = await load();

    expect(defaults?.purity.toApiBits(), '100');
  });

  group('backfill', () {
    test('syncs a key that predates the sync — the upgrade case, where the '
        'feature would otherwise never run', () async {
      final FakeWallhavenApi api = FakeWallhavenApi(account: _explicitAccount);
      final FakeSettingsRepository settings = FakeSettingsRepository();
      final LoadAccountDefaults load = _load(
        api: api,
        settings: settings,
        storedKey: 'abc123',
      );

      expect(await load(), _explicitAccount);
      expect(api.accountSettingsCalls, 1);
      // Written, so the next load costs nothing.
      expect(settings.accountSaved, _explicitAccount);
    });

    test('costs nothing once the defaults are there', () async {
      final FakeWallhavenApi api = FakeWallhavenApi();
      final LoadAccountDefaults load = _load(
        api: api,
        stored: _explicitAccount,
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

/// An account that browses anime, allows sketchy *and* explicit, and tops by
/// the week — so every field is distinguishable from tela's own defaults.
const AccountSettings _explicitAccount = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy, Purity.nsfw}),
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
