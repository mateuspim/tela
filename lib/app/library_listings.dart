import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';

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

/// The ids in [recentDownloadsProvider] whose downloaded file is gone.
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
          if (!readable[i]) recent[i].wallpaper.id,
      };
    });
