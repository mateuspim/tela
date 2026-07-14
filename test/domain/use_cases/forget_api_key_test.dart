import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/use_cases/forget_api_key.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_settings_repository.dart';

void main() {
  test('drops the stored key', () async {
    final FakeSecretStore secrets = FakeSecretStore(storedKey: 'abc123');

    await ForgetApiKey(
      secrets: secrets,
      settings: FakeSettingsRepository(),
    )();

    expect(secrets.storedKey, isNull);
    expect(await secrets.hasApiKey(), isFalse);
  });

  test('drops the account defaults with it — they outlive their key by '
      'exactly one 401 otherwise', () async {
    final FakeSettingsRepository settings = FakeSettingsRepository(
      accountDefaults: const AccountSettings(
        categories: CategoryFilter.all,
        topRange: TopRange.oneMonth,
      ),
    );

    await ForgetApiKey(
      secrets: FakeSecretStore(storedKey: 'abc123'),
      settings: settings,
    )();

    expect(settings.accountSaved, isNull);
  });

  test('forgetting nothing is not an error', () {
    final ForgetApiKey forgetApiKey = ForgetApiKey(
      secrets: FakeSecretStore(),
      settings: FakeSettingsRepository(),
    );

    expect(forgetApiKey(), completes);
  });
}
