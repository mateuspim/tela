import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// What this device has downloaded, so it can be set again without re-fetching.
///
/// A pure-domain port: Wallhaven has no idea these exist, and the fact that its
/// adapter speaks SQL is not something a use case may observe.
///
/// Two kinds of download are never recorded here, and the second is the one
/// that is easy to get wrong.
///
/// **Nothing in [StorageTier.appPrivate] is ever recorded, whatever its
/// purity.** The rule is about the *destination*, not the wallpaper: a safe
/// wallpaper the user deliberately sent to the private tier — by config, or by
/// the per-download override — was sent there to be private, and the private
/// library is already that tier's index. A history row is the opposite of an
/// index behind `FLAG_SECURE` and an app-lock: it is an ungated, backed-up
/// list of thumbnails, URLs and file locations, which is precisely what the
/// tier exists to prevent. Purity says nothing about that; the destination
/// does.
///
/// **Explicit wallpapers are never recorded here either**, in any tier, for
/// the same reason arriving from the other side: their home is the private
/// library.
///
/// Implementations enforce both themselves; callers must not have to remember.
abstract interface class DownloadHistory {
  /// Every recorded download, most recent first.
  ///
  /// Never explicit ones, and never app-private ones — the same two rules
  /// [record] applies, applied again on the way out.
  Future<List<DownloadRecord>> downloads();

  /// Records one completed download, replacing any earlier row for the same id.
  ///
  /// Silently keeps the two excluded kinds out rather than throwing: the file
  /// is already safely on disk by the time this runs, and a refused *history*
  /// write must not read to the user as a failed download.
  Future<void> record({
    required Wallpaper wallpaper,
    required StorageTier tier,
    required Uri location,
    TagFolder? tag,
  });

  /// Re-points [ref]'s row at a file that has moved to [tag].
  ///
  /// A retag changes both where the file is and what it is filed under, and the
  /// two must land together: a row naming the new tag beside the old location
  /// describes a file that is not there, which is the same broken state a
  /// half-applied tier move would leave. A no-op for a wallpaper that is not
  /// recorded — the private tier keeps no rows and retags there just as much.
  Future<void> retag({
    required WallpaperRef ref,
    required Uri location,
    required TagFolder? tag,
  });

  /// Re-points [ref]'s row at a file that has moved to another **tier**.
  ///
  /// [retag]'s wider sibling, and the field it adds is the load-bearing one:
  /// a delete routes by the tier on the row, so a wallpaper moved from the
  /// gallery to the files folder whose row still says `sharedGallery` names a
  /// MediaStore image that is not there.
  ///
  /// **Moving into a tier this list may not hold drops the row instead**,
  /// which is why this is one call and not "update, then remember to forget".
  /// The two exclusions in this port's docstring are the destination's
  /// property, so an implementation applies them here exactly as [record] does
  /// — a caller must not have to remember which tiers keep rows.
  ///
  /// A no-op for a wallpaper that is not recorded, as [retag] and [forget] are:
  /// a move *out of* the private library has no row to re-point, and it does
  /// not gain one here.
  Future<void> relocate({
    required WallpaperRef ref,
    required StorageTier tier,
    required Uri location,
    TagFolder? tag,
  });

  /// Forgets the row for [ref]. **Does not touch the downloaded file.**
  ///
  /// The history is an index, not a folder, and this is the only honest thing
  /// "remove" can mean here: the file lives in the gallery or under the user's
  /// own SAF tree, where Photos and every file manager can already delete it,
  /// and tela deleting it from behind a tile that merely *looks* like a file is
  /// how someone loses a wallpaper they meant to keep. The UI says so in the
  /// words of the confirmation, not just in this docstring.
  ///
  /// A no-op for a wallpaper that is not recorded — forgetting twice is not
  /// an error.
  Future<void> forget(WallpaperRef ref);

  /// Forgets every row in [refs], in as few writes as the adapter can manage.
  ///
  /// The bulk sibling of [forget], for a batch that may run into the hundreds
  /// — a stale-history cleanup ticks every row whose file is already gone, and
  /// [forget] awaited in a loop paid one round trip per row for it, which is
  /// what a large cleanup visibly stalled on. Same contract as [forget]
  /// otherwise: a ref that is not recorded is silently skipped, not an error.
  Future<void> forgetAll(Iterable<WallpaperRef> refs);
}
