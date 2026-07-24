import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

/// The registry: every source tela can browse, in the order the switcher
/// offers them.
///
/// **Adding a source is one adapter and one entry here.** Nothing else in the
/// app may name a site: features read [activeWallpaperSourceProvider] and its
/// capabilities, never a particular adapter.
final Provider<List<WallpaperSource>> wallpaperSourcesProvider =
    Provider<List<WallpaperSource>>(
      (Ref ref) => <WallpaperSource>[
        ref.watch(wallhavenSourceProvider),
        ref.watch(konachanSourceProvider),
      ],
    );

/// Which source browse is on, persisted across launches.
final AsyncNotifierProvider<ActiveSourceController, SourceId>
activeSourceProvider = AsyncNotifierProvider<ActiveSourceController, SourceId>(
  ActiveSourceController.new,
);

/// The source every listing goes to right now.
///
/// Resolves the stored id against the registry, **falling back to the first
/// registered source** while the read is in flight or when the stored id names
/// a source this build no longer has. Falling back rather than throwing is the
/// honest reading of "the app was downgraded, or a source was retired": a
/// browsable wall beats an error screen, and the switcher still shows where it
/// landed.
final Provider<WallpaperSource> activeWallpaperSourceProvider =
    Provider<WallpaperSource>((Ref ref) {
      final List<WallpaperSource> sources = ref.watch(wallpaperSourcesProvider);
      final SourceId? active = ref.watch(activeSourceProvider).value;
      return sources
              .where((WallpaperSource source) => source.id == active)
              .firstOrNull ??
          sources.first;
    });

/// The source one wallpaper came from — what a *stored* wallpaper's detail
/// screen must re-fetch through.
///
/// Not the active source: a favorite opened from the library belongs to
/// whichever site issued it, and asking the wrong one for its id would answer
/// with someone else's wallpaper or with nothing.
///
/// Throws [ArgumentError] naming the id when no registered source matches,
/// which can only happen to a row written by a build that had a source this
/// one does not.
final ProviderFamily<WallpaperSource, SourceId> wallpaperSourceForProvider =
    Provider.family<WallpaperSource, SourceId>((Ref ref, SourceId id) {
      final List<WallpaperSource> sources = ref.watch(wallpaperSourcesProvider);
      final WallpaperSource? match = sources
          .where((WallpaperSource source) => source.id == id)
          .firstOrNull;
      if (match == null) {
        throw ArgumentError(
          'no registered source for "$id"; this build knows '
          '${sources.map((WallpaperSource s) => s.id).join('|')}',
        );
      }
      return match;
    });

/// Loads the chosen source and writes a switch straight back through the port.
///
/// Same no-save-button shape as the other settings controllers: a screen that
/// can be closed mid-edit should not be able to lose the edit.
class ActiveSourceController extends AsyncNotifier<SourceId> {
  @override
  Future<SourceId> build() {
    return ref.watch(settingsRepositoryProvider).loadActiveSource();
  }

  /// Browses [source] from now on.
  ///
  /// The query is *not* carried over — see `BrowseQueryController`, which
  /// resets it. Filters are not portable between sources: one site's tag
  /// vocabulary, categories and sortings mean nothing on another, and carrying
  /// them would silently drop the halves the new source cannot honour.
  Future<void> choose(SourceId source) async {
    if (state.value == source) return;
    // Persist before switching: a source that lit up but did not save is one
    // the user believes they are on until the next cold start says otherwise.
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    await settings.saveActiveSource(source);
    state = AsyncData<SourceId>(source);
  }
}
