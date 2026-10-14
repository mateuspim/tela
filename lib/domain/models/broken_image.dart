import 'package:meta/meta.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image_condition.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// One stored image whose bytes are damaged, with everything a repair needs to
/// put a good copy back where it was.
///
/// [location] may name an explicit file, so — as with `PrivateImage` —
/// [toString] leaves it out: CLAUDE.md forbids logging NSFW paths.
///
/// ```dart
/// BrokenImage(ref: ref, tier: tier, location: uri,
///     condition: StoredImageCondition.empty, recorded: false);
/// ```
@immutable
class BrokenImage {
  /// Creates a damaged-file entry.
  const BrokenImage({
    required this.ref,
    required this.tier,
    required this.location,
    required this.condition,
    required this.recorded,
    this.tag,
  });

  /// Which wallpaper it should have been — what the repair fetches again.
  final WallpaperRef ref;

  /// The tier the file sits in, and the one the fresh copy is written to.
  final StorageTier tier;

  /// The tag folder it sits in, kept so the fresh copy lands beside it.
  final TagFolder? tag;

  /// The damaged file itself. Never log this.
  final Uri location;

  /// How it is damaged.
  final StoredImageCondition condition;

  /// Whether a download-history row points at it.
  ///
  /// Only those rows may be forgotten when the file has to go: a private
  /// image's ref can also name a *different*, healthy download with a row of
  /// its own, and forgetting by ref would drop that one too.
  final bool recorded;

  /// The same file, judged [found].
  BrokenImage withCondition(StoredImageCondition found) => BrokenImage(
    ref: ref,
    tier: tier,
    tag: tag,
    location: location,
    condition: found,
    recorded: recorded,
  );

  @override
  bool operator ==(Object other) =>
      other is BrokenImage &&
      other.ref == ref &&
      other.tier == tier &&
      other.tag == tag &&
      other.location == location &&
      other.condition == condition &&
      other.recorded == recorded;

  @override
  int get hashCode =>
      Object.hash(ref, tier, tag, location, condition, recorded);

  @override
  String toString() =>
      'BrokenImage(${ref.key}, ${tier.name}, ${condition.name})';
}
