import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/secrets/unavailable_secret_store.dart';

void main() {
  test('clean edition secret store can never acquire a credential', () async {
    const UnavailableSecretStore store = UnavailableSecretStore();

    expect(await store.readApiKey(), isNull);
    expect(await store.hasApiKey(), isFalse);
    expect(() => store.writeApiKey('secret'), throwsUnsupportedError);
  });
}
