import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/use_cases/sync_account_defaults.dart';

import '../../fakes/fake_settings_repository.dart';
import '../../fakes/fake_wallhaven_api.dart';

void main() {
  test('keeps what the account answered with', () async {
    final FakeSettingsRepository settings = FakeSettingsRepository();
    final SyncAccountDefaults sync = SyncAccountDefaults(
      api: FakeWallhavenApi(account: _account),
      settings: settings,
    );

    final AccountSettings synced = await sync();

    expect(synced, _account);
    expect(settings.accountSaved, _account);
  });

  test('costs one request — the account is not polled', () async {
    final FakeWallhavenApi api = FakeWallhavenApi(account: _account);
    final SyncAccountDefaults sync = SyncAccountDefaults(
      api: api,
      settings: FakeSettingsRepository(),
    );

    await sync();

    expect(api.accountSettingsCalls, 1);
  });

  test('stores nothing when the key is rejected', () async {
    final FakeSettingsRepository settings = FakeSettingsRepository();
    final SyncAccountDefaults sync = SyncAccountDefaults(
      api: FakeWallhavenApi(failure: const InvalidApiKeyFailure()),
      settings: settings,
    );

    await expectLater(sync.call, throwsA(isA<InvalidApiKeyFailure>()));
    expect(settings.accountSaved, isNull);
  });

  test('replaces the defaults of the key it replaces', () async {
    final FakeSettingsRepository settings = FakeSettingsRepository(
      accountDefaults: _account,
    );
    final SyncAccountDefaults sync = SyncAccountDefaults(
      api: FakeWallhavenApi(account: _otherAccount),
      settings: settings,
    );

    await sync();

    expect(settings.accountSaved, _otherAccount);
  });
}

const AccountSettings _account = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
  topRange: TopRange.oneWeek,
);

const AccountSettings _otherAccount = AccountSettings(
  categories: CategoryFilter(<Category>{Category.people}),
  purity: PurityFilter(<Purity>{Purity.nsfw}),
  topRange: TopRange.oneYear,
);
