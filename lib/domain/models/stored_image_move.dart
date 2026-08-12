import 'package:meta/meta.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// One already-downloaded image asking to change tier, without the network.
///
/// A single value so a batch is a list of these and the two directions —
/// into the private library and back out of it — differ only in how the list is
/// built, not in what moves it.
///
/// [purity] is what the destination is checked against, and it is the field to
/// read this class's docstring for. Moving *in*, it is the wallpaper's real
/// purity, taken from the history row. Moving *out*, it is
/// **[Purity.nsfw], always** — not because the image is explicit, but because
/// the app-private tier keeps no record of what it holds beyond a file name, so
/// tela cannot prove otherwise. The storage adapter's own gate then makes a
/// gallery destination impossible by construction, which is where the NSFW
/// invariant is supposed to be enforced rather than in a caller's `if`.
///
/// ```dart
/// StoredImageMove(
///   ref: record.wallpaper.ref,
///   purity: record.wallpaper.purity,
///   from: record.tier,
///   location: record.location,
///   to: StorageTier.appPrivate,
/// );
/// ```
@immutable
class StoredImageMove {
  /// Describes one image's move from [from] to [to].
  const StoredImageMove({
    required this.ref,
    required this.purity,
    required this.from,
    required this.location,
    required this.to,
    this.tag,
  });

  /// Which source issued the image and under what id — how the moved file is
  /// named in its new tier, and what history row to forget afterwards.
  final WallpaperRef ref;

  /// What the destination is checked against. See the class docstring: leaving
  /// the private tier this is always [Purity.nsfw].
  final Purity purity;

  /// The tier the file is in now — what the source delete has to route by.
  final StorageTier from;

  /// Where the file sits now: a MediaStore or document URI, or a local file
  /// URI. **Never log this** — it may name a private image.
  final Uri location;

  /// Where it should end up.
  final StorageTier to;

  /// The tag folder to file it under on arrival, or null for the tier root.
  ///
  /// Independent of [to]: a move can change the tier, the tag, or both. A
  /// same-tier move carrying a new tag is a **retag** that fell back to
  /// copy-and-delete because the file could not be moved in place — see
  /// `RetagStoredImages`.
  final TagFolder? tag;

  @override
  bool operator ==(Object other) =>
      other is StoredImageMove && other.ref == ref && other.to == to;

  @override
  int get hashCode => Object.hash(ref, to);

  /// Names the image and the tiers, and never the location — the same rule
  /// `PrivateImage` and `DownloadRecord` follow.
  @override
  String toString() => 'StoredImageMove($ref, ${from.name} → ${to.name})';
}
