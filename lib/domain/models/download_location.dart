import 'package:meta/meta.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';

/// Everything the location picker needs: where downloads go now, and whether a
/// card is even an option.
///
/// One model rather than two calls so the row draws from a single snapshot —
/// asking "is there a card" separately from "where do we write" invites the two
/// to disagree by a frame.
///
/// ```dart
/// const DownloadLocation(folder: null, sdCardAvailable: true);
/// // no folder chosen yet, but a card is in the slot to offer
/// ```
@immutable
class DownloadLocation {
  /// Creates a snapshot of the download location and the volumes on offer.
  const DownloadLocation({
    required this.folder,
    required this.sdCardAvailable,
  });

  /// The folder currently granted, or null when none has been.
  final DownloadFolder? folder;

  /// Whether a removable card is mounted right now, card chosen or not.
  final bool sdCardAvailable;

  /// The volume downloads currently write to, or null when none is set.
  StorageVolumeKind? get currentKind => folder?.kind;

  /// Whether the SD-card option should be shown at all.
  ///
  /// True when a card is in the slot, and also when the *current* folder is
  /// already on a card that has since been ejected — hiding it then would erase
  /// the user's own choice from the screen rather than mark it unavailable.
  bool get offersSdCard => sdCardAvailable || (folder?.isRemovable ?? false);

  @override
  bool operator ==(Object other) {
    return other is DownloadLocation &&
        other.folder == folder &&
        other.sdCardAvailable == sdCardAvailable;
  }

  @override
  int get hashCode => Object.hash(folder, sdCardAvailable);
}
