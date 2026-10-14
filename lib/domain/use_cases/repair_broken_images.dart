import 'package:tela/domain/models/broken_image.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/repair_tally.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Looks a wallpaper up again by the ref its file name carries.
typedef FetchWallpaper = Future<Wallpaper> Function(WallpaperRef ref);

/// Stores [wallpaper] into [tier] under [tag] and answers where it landed —
/// `DownloadWallpaper` with the destination pinned.
typedef StoreWallpaper =
    Future<StoredImage> Function(
      Wallpaper wallpaper, {
      required StorageTier tier,
      TagFolder? tag,
    });

/// How far a repair has got: [done] of [total] images settled.
typedef RepairProgress = void Function(int done, int total);

/// Puts a good copy back in place of each broken image, or removes it.
///
/// **Re-download first, delete only on failure.** The owner asked for "delete,
/// then re-download" (2026-10-07); a download over the same name already
/// replaces the file in place on all three tiers, so deleting first would only
/// add a system prompt for every gallery image and lose the file's slot for
/// nothing. What is kept is the outcome: no broken file survives a repair
/// unless even its delete fails.
///
/// One at a time, deliberately: every repair is a source lookup, and
/// Wallhaven allows 45 a minute.
///
/// ```dart
/// final RepairTally tally = await repair(broken, onProgress: report);
/// ```
class RepairBrokenImages {
  /// Creates the repair over the source, the download, and the two stores.
  const RepairBrokenImages({
    required FetchWallpaper fetch,
    required StoreWallpaper store,
    required ImageStore imageStore,
    required DownloadHistory history,
  }) : _fetch = fetch,
       _store = store,
       _imageStore = imageStore,
       _history = history;

  final FetchWallpaper _fetch;
  final StoreWallpaper _store;
  final ImageStore _imageStore;
  final DownloadHistory _history;

  /// Repairs every image in [broken], and answers how each went.
  Future<RepairTally> call(
    List<BrokenImage> broken, {
    RepairProgress? onProgress,
  }) async {
    final List<BrokenImage> unrepaired = <BrokenImage>[];
    for (int i = 0; i < broken.length; i++) {
      if (!await _redownload(broken[i])) unrepaired.add(broken[i]);
      onProgress?.call(i + 1, broken.length);
    }
    final int removed = await _remove(unrepaired);
    return RepairTally(
      repaired: broken.length - unrepaired.length,
      removed: removed,
      failed: unrepaired.length - removed,
    );
  }

  /// Fetches [image] again into its own tier and folder; false if it could
  /// not be had — gone from the source, no key for it, offline, or a build
  /// that may not store it. The adapters behind [FetchWallpaper] and
  /// [StoreWallpaper] answer the last two as these same failures, so only
  /// exceptions are caught here, never errors.
  Future<bool> _redownload(BrokenImage image) async {
    try {
      // Same source, same id, same name: the store overwrites the broken file
      // in place. Its answer is not compared against [BrokenImage.location] —
      // one file can carry two spellings of URI, and treating a different
      // spelling as "landed elsewhere" would delete the good copy.
      await _store(
        await _fetch(image.ref),
        tier: image.tier,
        tag: image.tag,
      );
      return true;
    } on SourceFailure {
      return false;
    } on ImageStoreFailure {
      return false;
    }
  }

  /// Deletes what could not be repaired, forgets the rows that pointed at it,
  /// and answers how many went.
  Future<int> _remove(List<BrokenImage> images) async {
    if (images.isEmpty) return 0;
    final Set<Uri> deleted = await _imageStore.deleteDownloads(
      <({StorageTier tier, Uri location})>[
        for (final BrokenImage image in images)
          (tier: image.tier, location: image.location),
      ],
    );
    await _history.forgetAll(<WallpaperRef>[
      for (final BrokenImage image in images)
        if (image.recorded && deleted.contains(image.location)) image.ref,
    ]);
    return deleted.length;
  }
}
