import 'package:meta/meta.dart';

/// How much disk one already-downloaded image takes, and which disk that is.
///
/// Two facts in one value because a caller that adds them up needs both at
/// once: "moving this frees 3.2 GB" is only true for the files that are **not**
/// on the card already, and asking the two questions separately invites the
/// answers to be paired by index twice.
///
/// A file that could not be measured — deleted from Photos, a revoked SAF
/// grant — is [zero] rather than an error, the same way `ImageStore.canRead`
/// answers false rather than throwing.
///
/// ```dart
/// const StoredImageSize(bytes: 3145728, onRemovableVolume: false);
/// ```
@immutable
class StoredImageSize {
  /// Creates a measurement of one stored file.
  const StoredImageSize({required this.bytes, required this.onRemovableVolume});

  /// What an unmeasurable file contributes: no bytes, and no claim about the
  /// volume it is not on.
  static const StoredImageSize zero = StoredImageSize(
    bytes: 0,
    onRemovableVolume: false,
  );

  /// The file's length on disk, or 0 when it could not be read.
  final int bytes;

  /// Whether the file already sits on a removable card.
  ///
  /// The reason this travels with the size: moving such a file to the card
  /// frees nothing, so counting it into a "space you get back" figure would
  /// promise the device bytes it never receives.
  final bool onRemovableVolume;

  @override
  bool operator ==(Object other) =>
      other is StoredImageSize &&
      other.bytes == bytes &&
      other.onRemovableVolume == onRemovableVolume;

  @override
  int get hashCode => Object.hash(bytes, onRemovableVolume);

  @override
  String toString() =>
      'StoredImageSize($bytes bytes, removable: $onRemovableVolume)';
}
