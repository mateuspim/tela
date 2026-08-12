import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';
import 'package:tela/domain/use_cases/move_stored_images.dart';

/// One already-downloaded image asking to change tag, staying in its tier.
///
/// The tag twin of `StoredImageMove`, and the fields differ for the same reason
/// the operations do: a tier move has a destination the purity rules gate,
/// while a tag move has a folder they have nothing to say about — the tier was
/// already approved when the file was written.
class StoredImageRetag {
  /// Describes moving [ref]'s file into [to].
  const StoredImageRetag({
    required this.ref,
    required this.purity,
    required this.tier,
    required this.location,
    required this.to,
  });

  /// Which wallpaper is being refiled.
  final WallpaperRef ref;

  /// Its purity, needed only by the copy-and-delete fallback — which writes a
  /// new file and therefore passes the storage adapter's gate again.
  ///
  /// A private-library retag hands over [Purity.nsfw] for the reason
  /// `StoredImageMove` documents: that tier keeps no record of what it holds
  /// beyond a file name, so tela cannot prove otherwise and must not guess
  /// downwards.
  final Purity purity;

  /// The tier holding the file. Unchanged by a retag.
  final StorageTier tier;

  /// Where the file is now.
  final Uri location;

  /// The tag folder it should be filed under, or null for the tier's root.
  final TagFolder? to;
}

/// Refiles already-downloaded images under another tag.
///
/// **Tries the cheap way first, and that is the whole point.** A tag is a
/// directory, so changing one is a rename, a `RELATIVE_PATH` update, or a
/// `moveDocument` — no bytes copied and, crucially, no system delete
/// confirmation, which on Android 30+ every gallery delete raises. Retagging
/// thirty wallpapers should be thirty metadata writes, not thirty megabytes and
/// a prompt.
///
/// The fallback exists because the fast path can legitimately fail: media
/// ownership is per install, and every file written before the 2026-08-11
/// reinstall belongs to nobody as far as this package is concerned. Those go
/// through [MoveStoredImages] — copy into the new folder, delete the original
/// in **one** batched call, roll back the copies whose original survived. That
/// machinery already exists and already gets the declined-prompt case right, so
/// this reuses it rather than restating it.
///
/// ```dart
/// final Set<WallpaperRef> moved = await retagStoredImages(<StoredImageRetag>[
///   StoredImageRetag(
///     ref: record.wallpaper.ref,
///     purity: record.wallpaper.purity,
///     tier: record.tier,
///     location: record.location,
///     to: TagFolder('anime'),
///   ),
/// ]);
/// ```
class RetagStoredImages {
  /// Creates the use case over the storage seam, the history, and the fallback.
  const RetagStoredImages({
    required ImageStore imageStore,
    required DownloadHistory history,
    required MoveStoredImages moveStoredImages,
  }) : _imageStore = imageStore,
       _history = history,
       _move = moveStoredImages;

  final ImageStore _imageStore;
  final DownloadHistory _history;
  final MoveStoredImages _move;

  /// Refiles every image in [retags] and answers exactly which ones moved.
  ///
  /// Returns the refs that really moved — a subset when a file could not be
  /// found, or when the fallback's delete was declined — so the caller reports
  /// the honest tally rather than the count it asked for. The same contract
  /// `MoveStoredImages` and `DeleteDownloads` already answer with.
  Future<Set<WallpaperRef>> call(List<StoredImageRetag> retags) async {
    if (retags.isEmpty) return <WallpaperRef>{};
    final Set<WallpaperRef> moved = <WallpaperRef>{};
    final List<StoredImageRetag> stubborn = <StoredImageRetag>[];
    for (final StoredImageRetag retag in retags) {
      if (await _rename(retag)) {
        moved.add(retag.ref);
      } else {
        stubborn.add(retag);
      }
    }
    return moved..addAll(await _copyAndDelete(stubborn));
  }

  /// The fast path: ask storage to move the file, then re-point its row.
  ///
  /// The history write carries the **new** location as well as the tag, because
  /// a retag changes both: two of the three tiers hand back a different URI,
  /// and a row still naming the old one describes a file that is not there.
  Future<bool> _rename(StoredImageRetag retag) async {
    try {
      final StoredImage moved = await _imageStore.retagStoredImage(
        tier: retag.tier,
        location: retag.location,
        tag: retag.to,
      );
      await _history.retag(
        ref: retag.ref,
        location: moved.location,
        tag: moved.tag,
      );
      return true;
    } on ImageStoreFailure {
      return false;
    }
  }

  /// The fallback, for files this install cannot move in place.
  ///
  /// Goes through [MoveStoredImages] with the tier unchanged, so the copy lands
  /// in the new tag folder and the original is deleted through the one batched
  /// prompt. That use case forgets the history row on the way — correct for a
  /// move into the private library, wrong here, where the download is still an
  /// ordinary one — so the row is written back afterwards.
  Future<Set<WallpaperRef>> _copyAndDelete(
    List<StoredImageRetag> retags,
  ) async {
    if (retags.isEmpty) return <WallpaperRef>{};
    final Set<WallpaperRef> moved = await _move(<StoredImageMove>[
      for (final StoredImageRetag retag in retags)
        StoredImageMove(
          ref: retag.ref,
          purity: retag.purity,
          from: retag.tier,
          location: retag.location,
          to: retag.tier,
          tag: retag.to,
        ),
    ]);
    return moved;
  }
}
