import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/ports/image_store.dart';

/// In-memory [ImageStore] that records the requested storage route.
class FakeImageStore implements ImageStore {
  /// Creates a fake that returns [storedImage] unless [failure] is set.
  FakeImageStore({
    this.failure,
    this.storedImage,
    List<PrivateImage> privateLibrary = const <PrivateImage>[],
    Set<Uri> unreadable = const <Uri>{},
  }) : _privateLibrary = List<PrivateImage>.of(privateLibrary),
       _unreadable = Set<Uri>.of(unreadable);

  /// Locations [canRead] answers false for — the files deleted behind tela's
  /// back, from Photos or a file manager.
  final Set<Uri> _unreadable;

  /// Failure thrown by every write when supplied.
  final ImageStoreFailure? failure;

  /// Value returned by a successful write.
  final StoredImage? storedImage;

  /// What the app-private tier currently holds, newest first.
  final List<PrivateImage> _privateLibrary;

  /// Ids passed to [deletePrivateImage], oldest first.
  final List<String> deletedIds = <String>[];

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

  @override
  Future<List<PrivateImage>> privateImages() async {
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return List<PrivateImage>.unmodifiable(_privateLibrary);
  }

  @override
  Future<void> deletePrivateImage(String id) async {
    deletedIds.add(id);
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    _privateLibrary.removeWhere((PrivateImage image) => image.id == id);
  }

  @override
  Future<bool> canRead(Uri location) async => !_unreadable.contains(location);
}
