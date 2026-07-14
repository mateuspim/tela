import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/use_cases/forget_api_key.dart';

import '../../fakes/fake_secret_store.dart';

void main() {
  test('drops the stored key', () async {
    final FakeSecretStore secrets = FakeSecretStore(storedKey: 'abc123');

    await ForgetApiKey(secrets: secrets)();

    expect(secrets.storedKey, isNull);
    expect(await secrets.hasApiKey(), isFalse);
  });

  test('forgetting nothing is not an error', () {
    final FakeSecretStore secrets = FakeSecretStore();

    expect(ForgetApiKey(secrets: secrets)(), completes);
  });
}
