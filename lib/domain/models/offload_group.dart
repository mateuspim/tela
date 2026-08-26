import 'package:meta/meta.dart';
import 'package:tela/domain/models/stored_image_move.dart';

/// One pile of already-downloaded images the offload screen can tick.
///
/// A pile, and not a tier: [OffloadKind.deviceFiles] is the files-outside-
/// gallery tier minus the part of it already on a card, because the whole point
/// of the screen is "what would this free", and a file already on the card
/// frees nothing.
enum OffloadKind {
  /// Downloads in `Pictures/tela`, visible in Photos. Moving them takes them
  /// out of the gallery index — the one consequence worth saying out loud.
  galleryDownloads,

  /// Files-outside-gallery downloads still sitting on built-in storage.
  ///
  /// Non-empty only when the granted folder was on the device, or was moved to
  /// a card after these were written. Nothing about them changes but the disk.
  deviceFiles,

  /// The app-private tier, which is built-in storage by definition.
  ///
  /// **Moving this is the one choice that changes more than a location.**
  /// A card has no app-private tier to land in, so these arrive in the files
  /// folder: still never gallery-indexed, but reachable by any file manager
  /// and by whatever the card is next plugged into, and no longer behind the
  /// app-lock. tela also stops listing them, as `MoveOutOfPrivate` already
  /// says of that direction.
  privateLibrary,
}

/// A tickable group: what would move, and how much it would free.
///
/// Carries the moves themselves rather than a count, so the screen that shows
/// the tally and the action that performs it cannot disagree about which files
/// they mean.
@immutable
class OffloadGroup {
  /// Creates a group over the moves it would perform.
  const OffloadGroup({
    required this.kind,
    required this.moves,
    required this.bytes,
  });

  /// Which pile this is.
  final OffloadKind kind;

  /// Every move this group would perform, already pointed at its destination.
  final List<StoredImageMove> moves;

  /// Bytes these files take on built-in storage right now — what the device
  /// gets back if they move.
  final int bytes;

  /// How many files are in the group.
  int get count => moves.length;

  @override
  bool operator ==(Object other) =>
      other is OffloadGroup &&
      other.kind == kind &&
      other.bytes == bytes &&
      other.count == count;

  @override
  int get hashCode => Object.hash(kind, bytes, count);

  @override
  String toString() => 'OffloadGroup(${kind.name}, $count files, $bytes bytes)';
}
