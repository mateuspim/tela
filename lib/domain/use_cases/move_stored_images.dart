import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Moves already-downloaded images from one storage tier to another.
///
/// The bytes never leave the device: each file is copied into its destination
/// and the original deleted. That is what makes "move this into the private
/// library" cost nothing but disk, where the alternative — delete, then
/// download again with an override — costs the whole file over the network and
/// needs a connection.
///
/// ```dart
/// final Set<WallpaperRef> moved = await moveStoredImages(<StoredImageMove>[
///   StoredImageMove(
///     ref: record.wallpaper.ref,
///     purity: record.wallpaper.purity,
///     from: record.tier,
///     location: record.location,
///     to: StorageTier.appPrivate,
///   ),
/// ]);
/// ```
class MoveStoredImages {
  /// Creates the use case over the storage and history seams.
  const MoveStoredImages({
    required ImageStore imageStore,
    required DownloadHistory history,
  }) : _imageStore = imageStore,
       _history = history;

  final ImageStore _imageStore;
  final DownloadHistory _history;

  /// Performs every move in [moves] and answers exactly which ones landed.
  ///
  /// Copy first, then delete the originals **in one call**, then undo the
  /// copies whose original survived. Each step is there for a reason:
  ///
  /// - The delete goes through [ImageStore.deleteDownloads] and not a loop over
  ///   the single delete, because on Android 30+ every gallery delete raises
  ///   its own system prompt — and thirty prompts for one "move these to the
  ///   private library" is not a feature, it is a punishment.
  /// - **The rollback is the load-bearing part.** The user can dismiss that
  ///   prompt, and a copy whose original is still there leaves the wallpaper in
  ///   *two* tiers — the one outcome a move must never produce, and the more
  ///   dangerous half of it is the copy sitting in the private library while
  ///   the original is still in Photos.
  ///
  /// Returns the refs that really moved — a subset when a copy failed or a
  /// delete was declined — so the caller reports the honest tally rather than
  /// the count it asked for. Mirrors `DeleteDownloads`, which returns what it
  /// deleted for the same reason.
  ///
  /// [onCopied] is called after each file is copied, with how many of
  /// [moves] have been written so far. A whole library moving to a card is
  /// minutes of copying, and an indeterminate spinner over it says nothing
  /// about whether it is halfway or stuck. The delete that follows is a single
  /// call and reports nothing, which is why this counts the copies and not the
  /// moves that finally landed.
  ///
  /// [stopped] is asked before each copy. **Stopping ends the copying, not the
  /// move**: everything already copied goes on to have its original deleted, so
  /// a user who stops a long batch keeps the files that had already made the
  /// trip rather than watching the work unwind. The answer is the honest
  /// subset, exactly as it is for a failure.
  ///
  /// [beforeDelete] is awaited between the two phases, and it is the seam a
  /// background move cannot do without. Only an Activity can raise the
  /// gallery's system delete confirmation, so with the app backgrounded that
  /// delete cannot happen — and a delete that did not happen reads here as a
  /// declined one, which undoes every copy behind it. A caller running in the
  /// background passes `AppVisibility.whenForeground` so the copying proceeds
  /// freely and only the prompt waits for a screen.
  Future<Set<WallpaperRef>> call(
    List<StoredImageMove> moves, {
    void Function(int copied, int total)? onCopied,
    bool Function()? stopped,
    Future<void> Function()? beforeDelete,
  }) async {
    if (moves.isEmpty) return <WallpaperRef>{};
    final Map<StoredImageMove, StoredImage> copied = await _copyAll(
      moves,
      onCopied,
      stopped,
    );
    if (copied.isEmpty) return <WallpaperRef>{};
    if (beforeDelete != null) await beforeDelete();
    final Set<Uri> gone = await _imageStore.deleteDownloads(
      <({StorageTier tier, Uri location})>[
        for (final StoredImageMove move in copied.keys)
          (tier: move.from, location: move.location),
      ],
    );
    return _settle(copied, gone);
  }

  /// Copies each source into its destination, dropping the ones that fail.
  ///
  /// A failure takes that move and no other: one unreadable file in a selection
  /// of thirty is a reason to report "moved 29 of 30", not to abandon the other
  /// twenty-nine.
  Future<Map<StoredImageMove, StoredImage>> _copyAll(
    List<StoredImageMove> moves,
    void Function(int copied, int total)? onCopied,
    bool Function()? stopped,
  ) async {
    final Map<StoredImageMove, StoredImage> copied =
        <StoredImageMove, StoredImage>{};
    for (int i = 0; i < moves.length; i++) {
      // Checked before the copy, never during: a half-written destination file
      // is the one thing a stop must not be able to produce.
      if (stopped?.call() ?? false) break;
      final StoredImage? made = await _copy(moves[i]);
      if (made != null) copied[moves[i]] = made;
      // Counts every attempt, not every success: this drives a progress bar,
      // and a bar that stalls on the one unreadable file in a hundred looks
      // like the move hung.
      onCopied?.call(i + 1, moves.length);
    }
    return copied;
  }

  Future<StoredImage?> _copy(StoredImageMove move) async {
    try {
      return await _imageStore.copyStoredImage(
        source: move.ref.source,
        id: move.ref.id,
        from: move.location,
        purity: move.purity,
        tier: move.to,
        tag: move.tag,
      );
    } on ImageStoreFailure {
      return null;
    }
  }

  /// Keeps the moves whose original really went, and undoes the rest.
  Future<Set<WallpaperRef>> _settle(
    Map<StoredImageMove, StoredImage> copied,
    Set<Uri> gone,
  ) async {
    final Set<WallpaperRef> moved = <WallpaperRef>{};
    for (final MapEntry<StoredImageMove, StoredImage> entry in copied.entries) {
      if (!gone.contains(entry.key.location)) {
        await _undo(entry.value);
        continue;
      }
      moved.add(entry.key.ref);
      await _settleHistory(entry.key, entry.value);
    }
    return moved;
  }

  /// What the move means for the history row, which depends on the
  /// **destination** and not on whether the tier changed at all.
  ///
  /// One call, because [DownloadHistory.relocate] already holds both outcomes:
  /// a move into the private library drops the row — a private download is
  /// never recorded, and a row outliving its file's move would be an ungated
  /// index of exactly what went private — and every other destination re-points
  /// it at the new tier, path and tag.
  ///
  /// **It used to forget every cross-tier move**, which was right for the only
  /// two directions that existed then (into the private library, and back out
  /// of it, where there is no row to begin with) and silently wrong for the one
  /// the offload screen added: moving the gallery into the files folder is an
  /// ordinary download changing shelves, and forgetting it would empty the
  /// download history of wallpapers that are still very much on the device.
  Future<void> _settleHistory(StoredImageMove move, StoredImage made) {
    return _history.relocate(
      ref: move.ref,
      tier: made.tier,
      location: made.location,
      tag: made.tag,
    );
  }

  /// Deletes a copy whose original survived. Swallows its own failure: the
  /// caller is already being told this one did not move, and a second error on
  /// the way out would replace that true report with a misleading one.
  Future<void> _undo(StoredImage copy) async {
    try {
      await _imageStore.deleteDownload(
        tier: copy.tier,
        location: copy.location,
      );
    } on ImageStoreFailure {
      return;
    }
  }
}
