import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/use_cases/load_account_defaults.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_settings_repository.dart';

void main() {
  test('answers null when no key was ever saved', () {
    final LoadAccountDefaults load = _load();

    expect(load(), completion(isNull));
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
}

/// An account that browses anime, allows sketchy *and* explicit, and tops by
/// the week — so every field is distinguishable from tela's own defaults.
const AccountSettings _explicitAccount = AccountSettings(
  categories: CategoryFilter(<Category>{Category.anime}),
  purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy, Purity.nsfw}),
  topRange: TopRange.oneWeek,
);

LoadAccountDefaults _load({AccountSettings? stored, String? storedKey}) {
  return LoadAccountDefaults(
    settings: FakeSettingsRepository(accountDefaults: stored),
    secrets: FakeSecretStore(storedKey: storedKey),
  );
}
