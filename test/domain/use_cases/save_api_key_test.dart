import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/domain/use_cases/save_api_key.dart';
import 'package:tela/domain/use_cases/sync_account_defaults.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_settings_repository.dart';
import '../../fakes/fake_wallhaven_api.dart';

void main() {
  test('stores the key and reports it verified when the account answers', () {
    final SaveApiKey saveApiKey = _saveApiKey(secrets: FakeSecretStore());

    expect(saveApiKey('abc123'), completion(ApiKeySaveOutcome.verified));
  });

  test('verifies with one /settings request — not a page of nsfw', () async {
    final FakeWallhavenApi api = FakeWallhavenApi();
    final SaveApiKey saveApiKey = _saveApiKey(api: api);

    await saveApiKey('abc123');

    expect(api.accountSettingsCalls, 1);
    expect(api.receivedQueries, isEmpty);
  });

  test('keeps the account defaults the verifying request answered', () async {
    final FakeSettingsRepository settings = FakeSettingsRepository();
    final SaveApiKey saveApiKey = _saveApiKey(
      api: FakeWallhavenApi(account: _animeAccount),
      settings: settings,
    );

    await saveApiKey('abc123');

    expect(settings.accountSaved, _animeAccount);
  });

  test('trims the key — a pasted key carries trailing whitespace', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = _saveApiKey(secrets: secrets);

    await saveApiKey('  abc123\n');

    expect(secrets.storedKey, 'abc123');
  });

  test('stores the key before verifying, or a good key would 401', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = _saveApiKey(
      secrets: secrets,
      api: KeyCheckingWallhavenApi(secrets: secrets, validKey: 'abc123'),
    );

    expect(saveApiKey('abc123'), completion(ApiKeySaveOutcome.verified));
  });

  test('rejects a blank key without touching the store', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = _saveApiKey(secrets: secrets);

    await expectLater(() => saveApiKey('   '), throwsArgumentError);
    expect(secrets.storedKey, isNull);
  });

  test('stores nothing when Wallhaven rejects the key', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final FakeSettingsRepository settings = FakeSettingsRepository();
    final SaveApiKey saveApiKey = _saveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(failure: const InvalidApiKeyFailure()),
      settings: settings,
    );

    await expectLater(
      () => saveApiKey('nope'),
      throwsA(isA<InvalidApiKeyFailure>()),
    );
    expect(secrets.storedKey, isNull);
    expect(settings.accountSaved, isNull);
  });

  test('puts the previous key back when a replacement is rejected', () async {
    final FakeSecretStore secrets = FakeSecretStore(storedKey: 'works');
    final FakeSettingsRepository settings = FakeSettingsRepository(
      accountDefaults: _animeAccount,
    );
    final SaveApiKey saveApiKey = _saveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(failure: const InvalidApiKeyFailure()),
      settings: settings,
    );

    await expectLater(
      () => saveApiKey('typo'),
      throwsA(isA<InvalidApiKeyFailure>()),
    );
    expect(secrets.storedKey, 'works');
    // The working key's defaults are still the working key's.
    expect(settings.accountSaved, _animeAccount);
  });

  test('keeps an unverifiable key when the device is offline', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final FakeSettingsRepository settings = FakeSettingsRepository();
    final SaveApiKey saveApiKey = _saveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(failure: const NetworkFailure()),
      settings: settings,
    );

    expect(await saveApiKey('abc123'), ApiKeySaveOutcome.savedUnverified);
    expect(secrets.storedKey, 'abc123');
    // Nothing was learned about the account, so nothing is half-stored.
    expect(settings.accountSaved, isNull);
  });

  test('keeps an unverifiable key when the check is rate-limited', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = _saveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(failure: const RateLimitedFailure()),
    );

    expect(await saveApiKey('abc123'), ApiKeySaveOutcome.savedUnverified);
    expect(secrets.storedKey, 'abc123');
  });
}

/// An account that browses somewhere other than tela's defaults, so adopting it
/// is visible.
const AccountSettings _animeAccount = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  topRange: TopRange.oneWeek,
);

SaveApiKey _saveApiKey({
  FakeSecretStore? secrets,
  WallhavenApi? api,
  FakeSettingsRepository? settings,
}) {
  return SaveApiKey(
    secrets: secrets ?? FakeSecretStore(),
    syncDefaults: SyncAccountDefaults(
      api: api ?? FakeWallhavenApi(),
      settings: settings ?? FakeSettingsRepository(),
    ),
  );
}

/// A [WallhavenApi] that behaves like Wallhaven does: it answers only when the
/// key it would send is the valid one.
///
/// It reads the key from the store the way `ApiKeyInterceptor` does at request
/// time, which is what makes it able to catch a use case that verifies *before*
/// it stores.
class KeyCheckingWallhavenApi implements WallhavenApi {
  /// Creates an API that accepts only [validKey], read from [secrets].
  const KeyCheckingWallhavenApi({
    required FakeSecretStore secrets,
    required String validKey,
  }) : _secrets = secrets,
       _validKey = validKey;

  final FakeSecretStore _secrets;
  final String _validKey;

  @override
  Future<AccountSettings> accountSettings() async {
    if (_secrets.storedKey != _validKey) throw const InvalidApiKeyFailure();
    return _animeAccount;
  }

  @override
  Future<WallpaperPage> search(SearchQuery query) async {
    if (!query.purity.requiresApiKey) return _empty;
    if (_secrets.storedKey == _validKey) return _empty;
    throw const InvalidApiKeyFailure();
  }

  @override
  Future<WallpaperDetails> wallpaperDetails(String id) {
    throw UnimplementedError('KeyCheckingWallhavenApi only answers searches');
  }

  static const WallpaperPage _empty = WallpaperPage(
    wallpapers: <Wallpaper>[],
    hasMore: false,
    currentPage: 1,
    lastPage: 1,
  );
}
