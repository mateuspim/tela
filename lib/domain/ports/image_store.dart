import 'package:tela/domain/models/private_image.dart';
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

  /// Everything in the app-private tier, most recently saved first.
  ///
  /// Only this tier can be listed, and that is the point: the other two write
  /// where the system gallery or a file manager already shows the result, while
  /// app-private files are visible to nothing but tela. Without this they are
  /// write-only, and uninstalling is the only way to get them back out.
  Future<List<PrivateImage>> privateImages();

  /// Deletes the app-private image with [id].
  ///
  /// Throws a safe `ImageStoreFailure` when there is nothing to delete.
  Future<void> deletePrivateImage(String id);
}
