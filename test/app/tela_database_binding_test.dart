import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_history.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/data/settings/drift_settings_repository.dart';
import 'package:tela/data/tag_blocklist/drift_tag_blocklist_repository.dart';

import '../fakes/fake_tag_blocklist_repository.dart';

/// [telaDatabaseProvider] must fail loudly when nobody bound it.
///
/// Regression cover for the seam that cost two harnesses: an unbound database
/// used to *open the real one*, and the resulting error surfaced far from its
/// cause — as an empty grid and a `RangeError` from tapping a tile that was
/// never built, never as anything naming a database.
void main() {
  test('an unbound database throws, naming itself and the way out', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(() => container.read(telaDatabaseProvider), _namesTheMissingBinding);
  });

  /// Every Drift-backed port, not just the blocklist. The grid's listen is what
  /// made this bite, but all four reach the same database, and all four used to
  /// open it. The error must still name the *database* — the port is where it
  /// surfaces, not what is wrong.
  test('every Drift-backed port refuses to build without a database', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    for (final ProviderBase<Object?> port in <ProviderBase<Object?>>[
      settingsRepositoryProvider,
      favoritesRepositoryProvider,
      downloadHistoryProvider,
      tagBlocklistRepositoryProvider,
    ]) {
      expect(
        () => container.read(port),
        _namesTheMissingBinding,
        reason: '$port must not silently reach the real database',
      );
    }
  });

  /// The refusal is about the *binding* being absent, not about Drift. Bound —
  /// as `main.dart` binds it with [openTelaDatabase] — every port builds its
  /// real adapter.
  test('a bound database builds every real Drift adapter', () {
    final TelaDatabase db = TelaDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[telaDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsRepositoryProvider),
      isA<DriftSettingsRepository>(),
    );
    expect(
      container.read(favoritesRepositoryProvider),
      isA<DriftFavoritesRepository>(),
    );
    expect(
      container.read(downloadHistoryProvider),
      isA<DriftDownloadHistory>(),
    );
    expect(
      container.read(tagBlocklistRepositoryProvider),
      isA<DriftTagBlocklistRepository>(),
    );
  });

  /// Overriding a *port* is the other way out, and the one a widget test should
  /// take: it must not drag the database in behind it.
  test('a faked port needs no database at all', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(tagBlocklistRepositoryProvider).blockedNames(),
      isEmpty,
    );
    expect(
      () => container.read(telaDatabaseProvider),
      _namesTheMissingBinding,
      reason: 'faking the port must not construct a database',
    );
  });
}

/// What the developer actually reads.
///
/// Pinned on the message rather than the exception type: Riverpod wraps a
/// provider's throw in its own `ProviderException`, which is theirs to change,
/// while naming the provider and the way out is the whole point of the guard
/// and is ours to keep.
final Matcher _namesTheMissingBinding = throwsA(
  isA<Object>().having(
    (Object error) => error.toString(),
    'toString',
    allOf(
      contains('telaDatabaseProvider'),
      contains('must be overridden'),
      contains('openTelaDatabase'),
    ),
  ),
);
