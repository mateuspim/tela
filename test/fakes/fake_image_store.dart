import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/ports/image_store.dart';

/// In-memory [ImageStore] that records the requested storage route.
class FakeImageStore implements ImageStore {
  /// Creates a fake that returns [storedImage] unless [failure] is set.
  FakeImageStore({
    this.failure,
    this.storedImage,
    this.folder,
    this.chosenFolder,
    this.sdCardAvailable = false,
    List<PrivateImage> privateLibrary = const <PrivateImage>[],
    Set<Uri> unreadable = const <Uri>{},
    Set<String> failingIds = const <String>{},
  }) : _privateLibrary = List<PrivateImage>.of(privateLibrary),
       _unreadable = Set<Uri>.of(unreadable),
       _failingIds = Set<String>.of(failingIds);

  /// Ids whose write throws while the rest succeed.
  ///
  /// [failure] fails every write, which cannot express the case a batch has to
  /// get right: some of the wallpapers stored and some of them not.
  final Set<String> _failingIds;

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
    if (_failingIds.contains(id)) {
      throw const ImageStoreFailure(ImageStoreProblem.source);
    }
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

  /// The folder already granted, or null for a tier nobody has configured.
  final DownloadFolder? folder;

  /// What the picker returns; null stands for the user backing out of it.
  ///
  /// Separate from [folder] so a test can say "they had none and chose one",
  /// which is the case the settings row exists for.
  final DownloadFolder? chosenFolder;

  /// Whether a removable card is on offer.
  final bool sdCardAvailable;

  /// The volume kinds passed to [chooseDownloadFolder], in order.
  final List<StorageVolumeKind> chosenKinds = <StorageVolumeKind>[];

  @override
  Future<DownloadLocation> downloadLocation() async => DownloadLocation(
    folder: _granted ?? folder,
    sdCardAvailable: sdCardAvailable,
  );

  @override
  Future<DownloadFolder?> chooseDownloadFolder(StorageVolumeKind kind) async {
    chosenKinds.add(kind);
    _granted = chosenFolder;
    return chosenFolder;
  }

  /// Set once the picker has run, so a later read sees what it granted.
  DownloadFolder? _granted;
}
