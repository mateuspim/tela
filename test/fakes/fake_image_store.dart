import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/ports/image_store.dart';

/// In-memory [ImageStore] that records the requested storage route.
class FakeImageStore implements ImageStore {
  /// Creates a fake that returns [storedImage] unless [failure] is set.
  FakeImageStore({this.failure, this.storedImage});

  /// Failure thrown by every write when supplied.
  final ImageStoreFailure? failure;

  /// Value returned by a successful write.
  final StoredImage? storedImage;

  /// Latest source image URL.
  String? receivedImageUrl;

  /// Latest Wallhaven image id.
  String? receivedId;

  /// Latest privacy classification.
  Purity? receivedPurity;

  /// Latest requested destination.
  StorageTier? receivedTier;

  @override
  Future<StoredImage> store({
    required String id,
    required String imageUrl,
    required Purity purity,
    required StorageTier tier,
  }) async {
    receivedId = id;
    receivedImageUrl = imageUrl;
    receivedPurity = purity;
    receivedTier = tier;
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return storedImage ??
        StoredImage(location: Uri.parse('memory://$id'), tier: tier);
  }
}
