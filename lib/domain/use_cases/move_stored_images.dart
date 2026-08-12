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
  Future<Set<WallpaperRef>> call(List<StoredImageMove> moves) async {
    if (moves.isEmpty) return <WallpaperRef>{};
    final Map<StoredImageMove, StoredImage> copied = await _copyAll(moves);
    if (copied.isEmpty) return <WallpaperRef>{};
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
  ) async {
    final Map<StoredImageMove, StoredImage> copied =
        <StoredImageMove, StoredImage>{};
    for (final StoredImageMove move in moves) {
      final StoredImage? made = await _copy(move);
      if (made != null) copied[move] = made;
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

  /// What the move means for the history row, which depends on whether the
  /// tier changed.
  ///
  /// **Across tiers, the row is forgotten.** A move *into* the private library
  /// must leave none behind: a private download is never recorded, and a row
  /// outliving its file's move would be an ungated index of exactly what went
  /// private. Moving *out* has no row to begin with, and `forget` is a
  /// documented no-op for a wallpaper that was never recorded.
  ///
  /// **Within one tier, the row is re-pointed instead.** That case is a retag
  /// falling back to copy-and-delete, and the download is still an ordinary
  /// one — forgetting it would delete the history for a file that is still
  /// sitting in the gallery, which is the opposite of what the user asked for.
  Future<void> _settleHistory(StoredImageMove move, StoredImage made) async {
    if (move.from != move.to) return _history.forget(move.ref);
    return _history.retag(
      ref: move.ref,
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
