import 'package:meta/meta.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// A successfully persisted image and its opaque platform location.
@immutable
class StoredImage {
  /// Creates the result of one image-store operation.
  const StoredImage({required this.location, required this.tier});

  /// Opaque content or file URI owned by the storage adapter.
  final Uri location;

  /// The tier which accepted the image.
  final StorageTier tier;
}
