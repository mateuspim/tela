import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/use_cases/browse_collections.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_settings_repository.dart';
import '../../fakes/fake_wallpaper_source.dart';

const CollectionRef _interiors = CollectionRef(
  source: SourceId.wallhaven,
  owner: 'jrmnt',
  id: '1797738',
);

const WallpaperCollection _row = WallpaperCollection(
  ref: _interiors,
  label: 'Interiors',
  count: 49,
  isPublic: true,
  views: 5201,
);

const WallpaperPage _emptyPage = WallpaperPage(
  wallpapers: <Wallpaper>[],
  currentPage: 1,
  hasMore: false,
);

({BrowseCollections use, FakeWallpaperSource source, FakeSecretStore secrets})
_wired({
  SourceCapabilities capabilities = wallhavenLikeCapabilities,
  String? storedUsername,
  String? apiKey,
}) {
  final FakeWallpaperSource source = FakeWallpaperSource(
    capabilities: capabilities,
    collections: <String, List<WallpaperCollection>>{
      'jrmnt': <WallpaperCollection>[_row],
    },
    collectionPages: <String, WallpaperPage>{_interiors.key: _emptyPage},
  );
  final FakeSecretStore secrets = FakeSecretStore();
  if (apiKey != null) secrets.storedKey = apiKey;
  final FakeSettingsRepository settings = FakeSettingsRepository()
    ..collectionsUsername = storedUsername;
  return (
    use: BrowseCollections(
      source: source,
      secrets: secrets,
      settings: settings,
    ),
    source: source,
    secrets: secrets,
  );
}

void main() {
  group("reading somebody's collections", () {
    test('answers what the source published', () async {
      final List<WallpaperCollection> found = await _wired().use.of('jrmnt');

      expect(found, <WallpaperCollection>[_row]);
    });

    test('needs no username stored, and no key', () async {
      // The zero-friction path: an uploader's public collections, reachable
      // from their listing with nothing configured at all.
      final List<WallpaperCollection> found = await _wired().use.of('jrmnt');

      expect(found, hasLength(1));
    });
  });

  group('reading your own collections', () {
    test('reads the stored username', () async {
      final List<WallpaperCollection> mine = await _wired(
        storedUsername: 'jrmnt',
      ).use.mine();

      expect(mine, <WallpaperCollection>[_row]);
    });

    test('refuses before the network when no username is stored', () async {
      // Its own failure, not a 404: Wallhaven cannot tell tela the difference
      // between "no such account" and "you never said who you are", so the
      // distinction is drawn here where it is still knowable.
      await expectLater(
        _wired().use.mine(),
        throwsA(isA<NoCollectionsUsernameFailure>()),
      );
    });
  });

  group('a source without collections', () {
    test('says so through the capability rather than failing late', () {
      expect(_wired(capabilities: narrowCapabilities).use.isSupported, isFalse);
      expect(_wired().use.isSupported, isTrue);
    });

    test('throws UnsupportedError when reached anyway', () {
      // A programming error, not a runtime one — the same contract
      // accountSettings() has on a source with no accounts. Synchronously,
      // and that is the point: it is not a failure a screen should be
      // awaiting and rendering, it is a call that should not have compiled
      // past a capability check.
      expect(
        () => _wired(capabilities: narrowCapabilities).use.of('jrmnt'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('the explicit-content guard', () {
    test('refuses an explicit page with no key, before any request', () async {
      final ({
        BrowseCollections use,
        FakeWallpaperSource source,
        FakeSecretStore secrets,
      })
      wired = _wired();

      await expectLater(
        wired.use.page(
          _interiors,
          page: 1,
          purity: const PurityFilter(<Purity>{Purity.nsfw}),
        ),
        throwsA(isA<InvalidApiKeyFailure>()),
      );
      // The point of guarding locally: a keyless explicit request is not
      // refused by Wallhaven here, it is answered *short* (measured live
      // 2026-08-26), which looks exactly like the collection itself.
      expect(wired.source.collectionPageCalls, isEmpty);
    });

    test('allows an explicit page once a key is stored', () async {
      final ({
        BrowseCollections use,
        FakeWallpaperSource source,
        FakeSecretStore secrets,
      })
      wired = _wired(apiKey: 'a-real-key');

      await wired.use.page(
        _interiors,
        page: 1,
        purity: const PurityFilter(<Purity>{Purity.nsfw}),
      );

      expect(wired.source.collectionPageCalls, hasLength(1));
    });

    test('never guards a safe page', () async {
      final ({
        BrowseCollections use,
        FakeWallpaperSource source,
        FakeSecretStore secrets,
      })
      wired = _wired();

      await wired.use.page(
        _interiors,
        page: 2,
        purity: PurityFilter.sfwOnly,
      );

      expect(wired.source.collectionPageCalls.single.page, 2);
      expect(
        wired.source.collectionPageCalls.single.purity.purities,
        <Purity>{Purity.sfw},
      );
    });
  });
}
