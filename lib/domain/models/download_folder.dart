import 'package:meta/meta.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';

/// Where the "files outside the gallery" tier actually writes.
///
/// The tier grants a folder through the system picker and then never mentions
/// it again, which is the hole this closes: the user picked a place once, at
/// download time, and had no way to see or change it afterwards.
///
/// A folder is described, never chosen, by this model — [isRemovable] and
/// [isAvailable] are facts about the volume it sits on, so a card that has been
/// pulled out is still the configured folder, just an absent one.
///
/// ```dart
/// const DownloadFolder(
///   volumeLabel: 'SD card',
///   relativePath: 'Wallpapers/tela',
///   isRemovable: true,
///   isAvailable: true,
///   freeBytes: 8 * 1024 * 1024 * 1024,
/// );
/// ```
@immutable
class DownloadFolder {
  /// Describes a folder already granted to tela.
  const DownloadFolder({
    required this.volumeLabel,
    required this.relativePath,
    required this.isRemovable,
    required this.isAvailable,
    this.freeBytes,
  });

  /// The volume's own name, as the system calls it — "SD card", "Internal
  /// storage". Never invented here: a made-up name would disagree with the
  /// picker the user chose it in.
  final String volumeLabel;

  /// Where inside the volume the files land, without a leading separator.
  ///
  /// Empty when the granted tree is the volume root.
  final String relativePath;

  /// Whether the volume can be physically removed — an SD card, not built-in
  /// storage.
  final bool isRemovable;

  /// Whether the volume is mounted and the grant still holds right now.
  ///
  /// False covers both an ejected card and a permission the system dropped;
  /// neither is worth distinguishing, because the user's next move is the same.
  final bool isAvailable;

  /// Free space on the volume, or null when it could not be read.
  ///
  /// Null rather than zero: "unknown" and "full" are opposite messages, and SAF
  /// offers no free-space API that always answers.
  final int? freeBytes;

  /// Which volume this folder sits on, derived from [isRemovable].
  ///
  /// Removability *is* the distinction the user picks by — "device or card" —
  /// so there is no separate flag to fall out of step with it.
  StorageVolumeKind get kind =>
      isRemovable ? StorageVolumeKind.sdCard : StorageVolumeKind.device;

  @override
  bool operator ==(Object other) {
    return other is DownloadFolder &&
        other.volumeLabel == volumeLabel &&
        other.relativePath == relativePath &&
        other.isRemovable == isRemovable &&
        other.isAvailable == isAvailable &&
        other.freeBytes == freeBytes;
  }

  @override
  int get hashCode => Object.hash(
    volumeLabel,
    relativePath,
    isRemovable,
    isAvailable,
    freeBytes,
  );
}
