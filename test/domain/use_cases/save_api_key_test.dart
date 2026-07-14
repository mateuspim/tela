import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/wallhaven_api.dart';
import 'package:tela/domain/use_cases/save_api_key.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_wallhaven_api.dart';

void main() {
  test('stores the key and reports it verified when Wallhaven serves nsfw', () {
    final FakeSecretStore secrets = FakeSecretStore();
    final FakeWallhavenApi api = FakeWallhavenApi();
    final SaveApiKey saveApiKey = SaveApiKey(secrets: secrets, api: api);

    expect(saveApiKey('abc123'), completion(ApiKeySaveOutcome.verified));
  });

  test('probes with nsfw purity — the request a bad key must fail', () async {
    final FakeWallhavenApi api = FakeWallhavenApi();
    final SaveApiKey saveApiKey = SaveApiKey(
      secrets: FakeSecretStore(),
      api: api,
    );

    await saveApiKey('abc123');

    expect(api.receivedQueries, hasLength(1));
    expect(api.receivedQueries.single.purity.toApiBits(), '001');
  });

  test('trims the key — a pasted key carries trailing whitespace', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = SaveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(),
    );

    await saveApiKey('  abc123\n');

    expect(secrets.storedKey, 'abc123');
  });

  test('stores the key before probing, or a good key would 401', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = SaveApiKey(
      secrets: secrets,
      api: KeyCheckingWallhavenApi(secrets: secrets, validKey: 'abc123'),
    );

    expect(saveApiKey('abc123'), completion(ApiKeySaveOutcome.verified));
  });

  test('rejects a blank key without touching the store', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = SaveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(),
    );

    await expectLater(() => saveApiKey('   '), throwsArgumentError);
    expect(secrets.storedKey, isNull);
  });

  test('stores nothing when Wallhaven rejects the key', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = SaveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(failure: const InvalidApiKeyFailure()),
    );

    await expectLater(
      () => saveApiKey('nope'),
      throwsA(isA<InvalidApiKeyFailure>()),
    );
    expect(secrets.storedKey, isNull);
  });

  test('puts the previous key back when a replacement is rejected', () async {
    final FakeSecretStore secrets = FakeSecretStore(storedKey: 'works');
    final SaveApiKey saveApiKey = SaveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(failure: const InvalidApiKeyFailure()),
    );

    await expectLater(
      () => saveApiKey('typo'),
      throwsA(isA<InvalidApiKeyFailure>()),
    );
    expect(secrets.storedKey, 'works');
  });

  test('keeps an unverifiable key when the device is offline', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = SaveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(failure: const NetworkFailure()),
    );

    expect(
      await saveApiKey('abc123'),
      ApiKeySaveOutcome.savedUnverified,
    );
    expect(secrets.storedKey, 'abc123');
  });

  test('keeps an unverifiable key when the probe is rate-limited', () async {
    final FakeSecretStore secrets = FakeSecretStore();
    final SaveApiKey saveApiKey = SaveApiKey(
      secrets: secrets,
      api: FakeWallhavenApi(failure: const RateLimitedFailure()),
    );

    expect(
      await saveApiKey('abc123'),
      ApiKeySaveOutcome.savedUnverified,
    );
    expect(secrets.storedKey, 'abc123');
  });
}

/// A [WallhavenApi] that behaves like Wallhaven does: it answers a search only
/// when the key it would send is the valid one.
///
/// It reads the key from the store the way `ApiKeyInterceptor` does at request
/// time, which is what makes it able to catch a use case that probes *before*
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
    currentPage: 1,
    lastPage: 1,
  );
}
