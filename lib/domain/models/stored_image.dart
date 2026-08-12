import 'package:meta/meta.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// A successfully persisted image and its opaque platform location.
@immutable
class StoredImage {
  /// Creates the result of one image-store operation.
  const StoredImage({required this.location, required this.tier, this.tag});

  /// Opaque content or file URI owned by the storage adapter.
  final Uri location;

  /// The tier which accepted the image.
  final StorageTier tier;

  /// The tag folder the image really landed in, or null for the tier root.
  ///
  /// What the adapter *did*, not what the caller asked for — the same contract
  /// [tier] has, and for the same reason. A write can end up untagged when the
  /// tier ignored the tag, and a history row claiming a tag the file is not
  /// filed under would send every later lookup to the wrong folder.
  final TagFolder? tag;
}
