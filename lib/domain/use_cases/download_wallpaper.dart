import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Downloads a wallpaper through the domain-owned storage port.
class DownloadWallpaper {
  /// Creates the use case over the project-owned [ImageStore] seam.
  const DownloadWallpaper({required ImageStore imageStore})
    : _imageStore = imageStore;

  final ImageStore _imageStore;

  /// Stores [wallpaper] in [tier], preserving its purity for safe routing.
  Future<StoredImage> call(Wallpaper wallpaper, StorageTier tier) {
    return _imageStore.store(
      id: wallpaper.id,
      imageUrl: wallpaper.fullImageUrl,
      purity: wallpaper.purity,
      tier: tier,
    );
  }
}
