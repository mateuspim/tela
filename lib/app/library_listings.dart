import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/features/favorites/favorites_providers.dart';

/// The two listings of what tela has already put on this device.
///
/// They live here, and not in the features that render them, for the reason
/// `accountDefaultsProvider` does: **a download is written from one feature and
/// read in another.** The detail screen invalidates both when a download lands;
/// the download history and the private library watch them. Features may not
/// import each other (CLAUDE.md), so they meet at the composition root.

/// Every recorded download, newest first — the history grid's whole source.
///
/// Reads from SQLite, never from Wallhaven, so it resolves offline. Explicit
/// downloads are not in here: they live in [privateImagesProvider].
final FutureProvider<List<DownloadRecord>> recentDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) {
      final DownloadHistory history = ref.watch(downloadHistoryProvider);
      return history.downloads();
    });

/// Everything in the app-private tier, newest first.
final FutureProvider<List<PrivateImage>> privateImagesProvider =
    FutureProvider<List<PrivateImage>>((Ref ref) {
      final ImageStore images = ref.watch(imageStoreProvider);
      return images.privateImages();
    });

/// The keys of every favorited wallpaper, as a set a tile can ask in O(1).
///
/// [WallpaperRef.key], not a bare id: the library is the one place wallpapers
/// from different sources sit side by side, so an id alone could mark the
/// wrong tile the day two sources issue the same one.
///
/// Set-shaped on purpose. A tile mark needs "is this one of mine?" for every
/// tile on a wall that can run to hundreds, and [isFavoriteProvider] answers
/// that one wallpaper at a time — a family watch and a SQLite round trip per
/// tile. This is the shape [missingDownloadsProvider] already uses for the
/// same job.
///
/// Derived from [favoritesProvider] rather than querying separately, so the
/// invalidation `refreshFavorites` already performs re-marks every shelf; a
/// third provider queried in parallel would need remembering there.
final FutureProvider<Set<String>> favoritedKeysProvider =
    FutureProvider<Set<String>>((Ref ref) async {
      final List<Wallpaper> saved = await ref.watch(favoritesProvider.future);
      return <String>{for (final Wallpaper w in saved) w.ref.key};
    });

/// The keys of every wallpaper tela has downloaded, as a set a tile can ask.
///
/// Two things it deliberately does not do:
///
/// - **It does not subtract [missingDownloadsProvider].** That probe opens
///   every recorded file, and the browse wall must not wait on a filesystem
///   sweep to draw a mark. The claim here is "you downloaded this", which stays
///   true even once the file is gone; the history shelf is where a deleted file
///   gets its own badge, because that is the screen where it changes what a tap
///   actually costs.
/// - **It does not include the private tier.** [recentDownloadsProvider]
///   excludes explicit downloads, and that exclusion is load-bearing here: a
///   mark fed from [privateImagesProvider] would let the browse grid — a screen
///   with no app-lock in front of it — disclose what is in the private library.
final FutureProvider<Set<String>> downloadedKeysProvider =
    FutureProvider<Set<String>>((Ref ref) async {
      final List<DownloadRecord> recent = await ref.watch(
        recentDownloadsProvider.future,
      );
      return <String>{
        for (final DownloadRecord d in recent) d.wallpaper.ref.key,
      };
    });

/// Re-reads every listing a finished download may have changed.
///
/// The counterpart to `refreshFavorites`, and it exists for the same reason:
/// which of these is stale depends on the wallpaper's purity, so dropping all
/// of them beats asking each caller to work it out. They are plain
/// (non-autoDispose) futures, so each resolves once per process and then
/// caches — without this a download lands on disk and in the database while the
/// screens that exist to show it keep rendering the world as it looked when
/// they were first opened. It presented as "the download did not save", and
/// only a relaunch made it appear (found on hardware, 2026-07-14).
///
/// [downloadedKeysProvider] needs no mention: it derives from
/// [recentDownloadsProvider], so the tile marks re-draw for free.
void refreshDownloads(WidgetRef ref) {
  ref
    ..invalidate(recentDownloadsProvider)
    ..invalidate(privateImagesProvider);
}

/// The keys in [recentDownloadsProvider] whose downloaded file is gone.
///
/// The history calls itself "wallpapers already on this device", and for a row
/// whose file was deleted from Photos or a file manager that is simply untrue —
/// tapping it still works, but it silently costs a full re-download and needs a
/// network the other rows do not. The tile says so instead of finding out for
/// you. tela is never told when a file it wrote is deleted, so the only way to
/// know is to look, and the only honest way to look is to open it.
///
/// Derived from the listing rather than folded into it, so a probe that hangs
/// or fails cannot keep the history off the screen: the grid renders from
/// [recentDownloadsProvider] and the badges arrive when they arrive.
final FutureProvider<Set<String>> missingDownloadsProvider =
    FutureProvider<Set<String>>((Ref ref) async {
      final List<DownloadRecord> recent = await ref.watch(
        recentDownloadsProvider.future,
      );
      final ImageStore images = ref.watch(imageStoreProvider);
      final List<bool> readable = await Future.wait(
        recent.map((DownloadRecord d) => images.canRead(d.location)),
      );
      return <String>{
        for (int i = 0; i < recent.length; i++)
          if (!readable[i]) recent[i].wallpaper.ref.key,
      };
    });
