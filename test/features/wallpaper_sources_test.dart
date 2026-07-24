import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';
import 'package:tela/features/browse/browse_query_controller.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// A second, deliberately narrower source. Named after nothing real: it exists
/// to prove the app reads capabilities rather than assuming Wallhaven's.
const SourceId _booru = SourceId('booru');

void main() {
  group('the registry', () {
    test('opens on Wallhaven, which is where every earlier build browsed', () {
      final ProviderContainer container = _container();

      expect(container.read(activeWallpaperSourceProvider).id, _wallhaven);
    });

    test('opens on the stored source once the setting resolves', () async {
      final FakeSettingsRepository settings = FakeSettingsRepository()
        ..activeSource = _booru;
      final ProviderContainer container = _container(settings: settings);

      await container.read(activeSourceProvider.future);

      expect(container.read(activeWallpaperSourceProvider).id, _booru);
    });

    test(
      'falls back rather than failing on a source this build lost',
      () async {
        // A downgrade, or a retired adapter. A browsable wall beats an error
        // screen, and the switcher still shows where it landed.
        final FakeSettingsRepository settings = FakeSettingsRepository()
          ..activeSource = const SourceId('gone');
        final ProviderContainer container = _container(settings: settings);

        await container.read(activeSourceProvider.future);

        expect(container.read(activeWallpaperSourceProvider).id, _wallhaven);
      },
    );

    test('choosing a source persists it before it takes effect', () async {
      final FakeSettingsRepository settings = FakeSettingsRepository();
      final ProviderContainer container = _container(settings: settings);
      await container.read(activeSourceProvider.future);

      await container.read(activeSourceProvider.notifier).choose(_booru);

      expect(settings.activeSource, _booru);
      expect(container.read(activeWallpaperSourceProvider).id, _booru);
    });

    test(
      'a wallpaper is refetched through its own source, not the active one',
      () async {
        final ProviderContainer container = _container();
        await container.read(activeSourceProvider.notifier).choose(_booru);

        // A favorite from Wallhaven opened while browsing the booru.
        expect(
          container.read(wallpaperSourceForProvider(_wallhaven)).id,
          _wallhaven,
        );
        expect(container.read(wallpaperSourceForProvider(_booru)).id, _booru);
      },
    );

    test('an unknown source names itself rather than answering wrongly', () {
      final ProviderContainer container = _container();

      expect(
        () =>
            container.read(wallpaperSourceForProvider(const SourceId('nope'))),
        // Riverpod wraps what a provider throws; the message is the part that
        // has to name the offending id.
        throwsA(
          isA<Object>().having(
            (Object e) => e.toString(),
            'message',
            allOf(contains('nope'), contains('wallhaven')),
          ),
        ),
      );
    });
  });

  group('switching sources', () {
    test('resets the listing, because filters are not portable', () async {
      final ProviderContainer container = _container();
      await container.read(activeSourceProvider.future);
      container.read(browseQueryProvider.notifier)
        ..search('sunset')
        ..applyFilters(
          const SearchQuery(purity: PurityFilter(<Purity>{Purity.sketchy})),
        );

      await container.read(activeSourceProvider.notifier).choose(_booru);

      final SearchQuery query = container.read(browseQueryProvider);
      expect(query.term, isEmpty);
      expect(query.purity.purities, <Purity>{Purity.sfw});
    });

    test('the setting merely resolving is not a switch', () async {
      // loading → data on the first read must not wipe a filter set before it
      // landed, which is the bug a plain `watch` in build() introduced.
      final ProviderContainer container = _container();
      container.read(browseQueryProvider.notifier).search('sunset');

      await container.read(activeSourceProvider.future);

      expect(container.read(browseQueryProvider).term, 'sunset');
    });
  });

  group('the NSFW key guard', () {
    test('refuses an explicit query on a source that needs a key', () {
      final SearchWallpapers search = SearchWallpapers(
        source: FakeWallpaperSource(),
        secrets: FakeSecretStore(),
        blocklist: FakeTagBlocklistRepository(),
      );

      expect(
        search(
          const SearchQuery(purity: PurityFilter(<Purity>{Purity.nsfw})),
        ),
        throwsA(isA<InvalidApiKeyFailure>()),
      );
    });

    test(
      'allows the same query on a source that serves it anonymously',
      () async {
        // Konachan does exactly this (verified live, 2026-07-24), so a
        // hardcoded guard would refuse one it would happily answer.
        final FakeWallpaperSource source = FakeWallpaperSource(
          id: _booru,
          capabilities: narrowCapabilities,
        );
        final SearchWallpapers search = SearchWallpapers(
          source: source,
          secrets: FakeSecretStore(),
          blocklist: FakeTagBlocklistRepository(),
        );

        await search(
          const SearchQuery(purity: PurityFilter(<Purity>{Purity.nsfw})),
        );

        expect(source.receivedQueries, hasLength(1));
      },
    );
  });
}

const SourceId _wallhaven = SourceId.wallhaven;

/// A container whose registry holds Wallhaven *and* a narrower second source.
ProviderContainer _container({FakeSettingsRepository? settings}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(
        settings ?? FakeSettingsRepository(),
      ),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      wallpaperSourcesProvider.overrideWithValue(<WallpaperSource>[
        FakeWallpaperSource(),
        FakeWallpaperSource(
          id: _booru,
          displayName: 'Booru',
          capabilities: narrowCapabilities,
        ),
      ]),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
