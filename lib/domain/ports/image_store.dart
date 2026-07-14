import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';

/// Stores a remote wallpaper using a user-selected storage tier.
///
/// Implementations enforce purity restrictions themselves; features must never
/// decide whether a destination is safe for an image.
abstract interface class ImageStore {
  /// Downloads and persists one image.
  ///
  /// Throws a safe `ImageStoreFailure`, never one containing [imageUrl] or a
  /// private local path.
  Future<StoredImage> store({
    required String id,
    required String imageUrl,
    required Purity purity,
    required StorageTier tier,
  });
}
