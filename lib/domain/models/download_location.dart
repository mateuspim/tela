import 'package:meta/meta.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/vault_folder.dart';

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
    this.vault = VaultFolder.standard,
    this.explicitFolder,
  });

  /// The folder safe and sketchy downloads go to, or null when none has been
  /// granted.
  final DownloadFolder? folder;

  /// The folder explicit downloads go to — its hidden vault, precisely — or
  /// null when none has been granted.
  ///
  /// Its own grant since the owner asked for the two to be placeable apart
  /// (2026-10-16). A device that never chose one separately reports the safe
  /// folder's tree here, with the vault inside it: the one-folder layout every
  /// earlier build wrote.
  final DownloadFolder? explicitFolder;

  /// Whether a removable card is mounted right now, card chosen or not.
  final bool sdCardAvailable;

  /// The hidden folder inside [explicitFolder] that explicit downloads land in.
  ///
  /// Here rather than in `StorageSettings` because it is a property of *where
  /// this tier writes*, not of which purity routes to it — the same reason the
  /// granted folder is here. It is reported whether or not a folder exists, so
  /// the settings row can name it before anything is configured.
  final VaultFolder vault;

  /// The volume safe downloads currently write to, or null when none is set.
  StorageVolumeKind? get currentKind => folder?.kind;

  /// The folder a download of [purity] writes to in the files tier.
  ///
  /// ```dart
  /// location.folderFor(Purity.sketchy); // folder — sketchy follows safe
  /// ```
  DownloadFolder? folderFor(Purity purity) {
    final bool explicit = StorageSettings.bucketFor(purity) == Purity.nsfw;
    return explicit ? explicitFolder : folder;
  }

  /// Whether the SD-card option should be shown at all.
  ///
  /// True when a card is in the slot, and also when the *current* folder is
  /// already on a card that has since been ejected — hiding it then would erase
  /// the user's own choice from the screen rather than mark it unavailable.
  bool get offersSdCard =>
      sdCardAvailable ||
      (folder?.isRemovable ?? false) ||
      (explicitFolder?.isRemovable ?? false);

  /// The disk a download to [tier] lands on, or null when that is not settled
  /// yet (the files tier before any folder is granted).
  ///
  /// Only the files tier follows the granted folder. The private library is
  /// app-internal storage and the gallery is the built-in MediaStore volume,
  /// whatever card the files tier points at — and the chooser naming that was
  /// missing: "Private library" read as "my private stuff, on the card I set
  /// up", so explicit downloads kept landing on the device (owner, 2026-10-16).
  ///
  /// ```dart
  /// location.volumeFor(StorageTier.appPrivate, Purity.nsfw); // device
  /// ```
  StorageVolumeKind? volumeFor(StorageTier tier, Purity purity) {
    final bool followsFolder = tier == StorageTier.filesOutsideGallery;
    return followsFolder ? folderFor(purity)?.kind : StorageVolumeKind.device;
  }

  @override
  bool operator ==(Object other) {
    return other is DownloadLocation &&
        other.folder == folder &&
        other.sdCardAvailable == sdCardAvailable &&
        other.vault == vault &&
        other.explicitFolder == explicitFolder;
  }

  @override
  int get hashCode =>
      Object.hash(folder, sdCardAvailable, vault, explicitFolder);
}
