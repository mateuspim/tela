import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

/// Reads user-assembled collections, and the wallpapers inside one.
///
/// The collections counterpart to `SearchWallpapers`, and it exists for the
/// same reason: three rules live here rather than in a screen or an adapter —
/// the source must actually have collections, your own account has to be
/// named before it can be read, and an explicit request still needs a key.
///
/// **The tag blocklist does not apply inside a collection, and cannot.**
/// `SearchWallpapers` folds every blocked tag into the query as an exclude, so
/// blocking a tag once keeps it out of every listing. A collection's contents
/// endpoint honours **only** `purity` — `tags` along with everything else is
/// accepted and silently ignored (measured live 2026-08-26, and stated in
/// Wallhaven's own API reference) — and its wallpapers arrive with no tag data
/// to filter on locally either, so there is nothing to fold in and nothing to
/// strain out afterwards. A blocked tag can therefore appear in a collection.
/// That is a real hole, it is the source's and not tela's, and it is named
/// here rather than papered over: the alternative would be one `/w/{id}` per
/// wallpaper, which is 24 requests a page against a 45/minute ceiling.
///
/// ```dart
/// final List<WallpaperCollection> mine = await collections.mine();
/// ```
class BrowseCollections {
  /// Creates the use case. Every collaborator is injected (CLAUDE.md: no
  /// global singletons).
  const BrowseCollections({
    required WallpaperSource source,
    required SecretStore secrets,
    required SettingsRepository settings,
  }) : _source = source,
       _secrets = secrets,
       _settings = settings;

  final WallpaperSource _source;
  final SecretStore _secrets;
  final SettingsRepository _settings;

  /// Whether the active source has collections at all.
  ///
  /// Read this before offering the feature; every other method here throws
  /// [UnsupportedError] on a source without them, which is a programming error
  /// rather than something to show a user.
  bool get isSupported => _source.capabilities.browsesCollections;

  /// The collections [username] publishes.
  Future<List<WallpaperCollection>> of(String username) {
    _guardSupported();
    return _source.collectionsOf(username);
  }

  /// The collections belonging to the stored username — private ones included,
  /// when a key is stored too.
  ///
  /// Throws [NoCollectionsUsernameFailure] when no username is stored, which
  /// is the state a fresh install is in.
  Future<List<WallpaperCollection>> mine() async {
    _guardSupported();
    final String? username = await _settings.loadCollectionsUsername();
    if (username == null) throw const NoCollectionsUsernameFailure();
    return _source.collectionsOf(username);
  }

  /// One page of [collection], at [purity].
  ///
  /// Throws [InvalidApiKeyFailure] when [purity] asks for explicit content on a
  /// source that needs a key and none is stored — before any network call, the
  /// same guard `SearchWallpapers` applies, so the two cannot answer the same
  /// question differently.
  Future<WallpaperPage> page(
    CollectionRef collection, {
    required int page,
    required PurityFilter purity,
  }) async {
    _guardSupported();
    await _guardNsfwRequiresKey(purity);
    return _source.collectionPage(collection, page: page, purity: purity);
  }

  void _guardSupported() {
    if (isSupported) return;
    throw UnsupportedError(
      '"${_source.id}" has no collections; '
      'guard on SourceCapabilities.browsesCollections',
    );
  }

  /// Refuses an explicit request the source would only under-serve.
  ///
  /// Worth being plain that the *symptom* differs from search: a keyless
  /// collection request for explicit content is not a 401, it is a quietly
  /// shorter list (measured live 2026-08-26 — collection `jrmnt/1651328`
  /// reports 82 wallpapers and answers 22 keylessly at `purity=111`). Refusing
  /// it here is still the right move, because a silently truncated listing is
  /// the worse of the two outcomes: it looks like the collection.
  Future<void> _guardNsfwRequiresKey(PurityFilter purity) async {
    if (!_source.capabilities.needsKeyFor(purity)) return;
    if (await _secrets.hasApiKey()) return;
    throw InvalidApiKeyFailure(
      'explicit purity requires an API key for "${_source.id}", '
      'but none is stored',
    );
  }
}
