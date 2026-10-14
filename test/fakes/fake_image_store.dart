import 'package:tela/domain/models/download_deletion.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/stored_image_condition.dart';
import 'package:tela/domain/models/stored_image_size.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/vault_folder.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
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
    Set<Uri> declined = const <Uri>{},
    this.galleryDeleteConfirmed = true,
  }) : _privateLibrary = List<PrivateImage>.of(privateLibrary),
       _unreadable = Set<Uri>.of(unreadable),
       _failingIds = Set<String>.of(failingIds),
       _declined = Set<Uri>.of(declined);

  /// Ids whose write throws while the rest succeed.
  ///
  /// [failure] fails every write, which cannot express the case a batch has to
  /// get right: some of the wallpapers stored and some of them not.
  final Set<String> _failingIds;

  /// Locations [canRead] answers false for — the files deleted behind tela's
  /// back, from Photos or a file manager.
  final Set<Uri> _unreadable;

  /// Locations whose [deleteDownload] answers [DownloadDeletion.declined] —
  /// standing in for the user dismissing the system delete prompt.
  final Set<Uri> _declined;

  /// What [galleryDeleteConfirmedBySystem] answers; true is the modern default.
  final bool galleryDeleteConfirmed;

  /// Failure thrown by every write when supplied.
  final ImageStoreFailure? failure;

  /// Value returned by a successful write.
  final StoredImage? storedImage;

  /// What the app-private tier currently holds, newest first.
  final List<PrivateImage> _privateLibrary;

  /// How many times [privateImages] — the listing that opens the vault — ran.
  ///
  /// Asserted at zero by the offload survey's tests. On a card that walk is a
  /// crossing per file, so *which* listing a caller reaches for is a fact worth
  /// pinning, not an implementation detail.
  int vaultListings = 0;

  /// Refs of private images passed to [deleteDownload], oldest first.
  final List<WallpaperRef> deletedRefs = <WallpaperRef>[];

  /// Every location [deleteDownload] actually removed, oldest first.
  final List<Uri> deletedLocations = <Uri>[];

  /// Tiers passed to [deleteDownload], oldest first.
  final List<StorageTier> deletedTiers = <StorageTier>[];

  /// The size of each [deleteDownloads] batch, in call order.
  ///
  /// Records the *shape* of the calls, not just their effect: the bulk delete
  /// exists to hand the whole selection over at once (one gallery prompt), and
  /// a loop over the single delete would leave every other expectation intact.
  final List<int> batchSizes = <int>[];

  /// Latest source image URL.
  String? receivedImageUrl;

  /// Latest image id, as its own source issued it.
  String? receivedId;

  /// Latest source the id belongs to — the other half of the on-disk file name.
  SourceId? receivedSource;

  /// Latest privacy classification.
  Purity? receivedPurity;

  /// Latest requested destination.
  StorageTier? receivedTier;

  /// Latest requested tag folder, null when the write was untagged.
  TagFolder? receivedTag;

  @override
  Future<StoredImage> store({
    required SourceId source,
    required String id,
    required String imageUrl,
    required Purity purity,
    required StorageTier tier,
    TagFolder? tag,
  }) async {
    receivedSource = source;
    receivedId = id;
    receivedImageUrl = imageUrl;
    receivedPurity = purity;
    receivedTier = tier;
    receivedTag = tag;
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    if (_failingIds.contains(id)) {
      throw const ImageStoreFailure(ImageStoreProblem.source);
    }
    return storedImage ??
        StoredImage(location: Uri.parse('memory://$id'), tier: tier, tag: tag);
  }

  /// Every local copy made, in call order — the moves that got as far as
  /// writing a destination file.
  final List<({Uri from, StorageTier tier, TagFolder? tag, WallpaperRef ref})>
  copies = <({Uri from, StorageTier tier, TagFolder? tag, WallpaperRef ref})>[];

  /// Every retag asked for, in call order.
  final List<({StorageTier tier, Uri location, TagFolder? tag})> retags =
      <({StorageTier tier, Uri location, TagFolder? tag})>[];

  /// Locations whose [retagStoredImage] throws, standing in for the file this
  /// install no longer owns — the case that must fall back to copy-and-delete.
  Set<Uri> unretaggable = <Uri>{};

  /// Applies the real NSFW gate, unlike [store].
  ///
  /// Deliberate, and the one place this fake enforces a rule rather than
  /// recording one: a move out of the private library hands over `nsfw` because
  /// it cannot prove otherwise, and the whole safety of that design is the
  /// adapter refusing the gallery. A fake that accepted it would let the test
  /// suite pass over exactly the arrangement that would leak an explicit image
  /// into Photos.
  @override
  Future<StoredImage> copyStoredImage({
    required SourceId source,
    required String id,
    required Uri from,
    required Purity purity,
    required StorageTier tier,
    TagFolder? tag,
  }) async {
    if (purity == Purity.nsfw && tier == StorageTier.sharedGallery) {
      throw const ImageStoreFailure(ImageStoreProblem.restricted);
    }
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    if (_failingIds.contains(id)) {
      throw const ImageStoreFailure(ImageStoreProblem.source);
    }
    copies.add((
      from: from,
      tier: tier,
      tag: tag,
      ref: WallpaperRef(source, id),
    ));
    return StoredImage(
      location: Uri.parse('memory://$id-copy'),
      tier: tier,
      tag: tag,
    );
  }

  /// Moves an image between tag folders without copying it.
  ///
  /// Answers a location derived from the tag, so a caller that forgets to store
  /// the new one is visible in a test rather than merely wrong on a device.
  @override
  Future<StoredImage> retagStoredImage({
    required StorageTier tier,
    required Uri location,
    required TagFolder? tag,
  }) async {
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    if (unretaggable.contains(location)) {
      throw const ImageStoreFailure(ImageStoreProblem.unavailable);
    }
    retags.add((tier: tier, location: location, tag: tag));
    return StoredImage(
      location: Uri.parse('memory://${tag?.name ?? 'untagged'}/$location'),
      tier: tier,
      tag: tag,
    );
  }

  @override
  Future<List<PrivateImage>> privateImages() async {
    vaultListings++;
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return List<PrivateImage>.unmodifiable(_privateLibrary);
  }

  /// The app-private rows only, as the native listing of that name answers.
  @override
  Future<List<PrivateImage>> appPrivateImages() async {
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return List<PrivateImage>.unmodifiable(<PrivateImage>[
      for (final PrivateImage image in _privateLibrary)
        if (image.tier == StorageTier.appPrivate) image,
    ]);
  }

  @override
  Future<DownloadDeletion> deleteDownload({
    required StorageTier tier,
    required Uri location,
  }) async {
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return _remove(tier, location)
        ? DownloadDeletion.deleted
        : DownloadDeletion.declined;
  }

  @override
  Future<Set<Uri>> deleteDownloads(
    List<({StorageTier tier, Uri location})> targets,
  ) async {
    batchSizes.add(targets.length);
    final ImageStoreFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return <Uri>{
      for (final ({StorageTier tier, Uri location}) target in targets)
        if (_remove(target.tier, target.location)) target.location,
    };
  }

  /// Deletes one location unless it is in [_declined], recording what it did.
  /// Returns whether it deleted, so both delete methods share the bookkeeping.
  bool _remove(StorageTier tier, Uri location) {
    if (_declined.contains(location)) return false;
    deletedTiers.add(tier);
    deletedLocations.add(location);
    final int index = _privateLibrary.indexWhere(
      (PrivateImage image) => image.location == location,
    );
    if (index >= 0) {
      deletedRefs.add(_privateLibrary[index].ref);
      _privateLibrary.removeAt(index);
    }
    return true;
  }

  @override
  Future<bool> galleryDeleteConfirmedBySystem() async => galleryDeleteConfirmed;

  @override
  Future<bool> canRead(Uri location) async => !_unreadable.contains(location);

  /// Counts its calls, so a test can prove the history probes its rows in
  /// **one** crossing rather than one per row — the whole point of the bulk
  /// method, and something an answer-only fake cannot show.
  int canReadAllCalls = 0;

  @override
  Future<List<bool>> canReadAll(List<Uri> locations) async {
    canReadAllCalls++;
    return <bool>[for (final Uri l in locations) !_unreadable.contains(l)];
  }

  /// Sizes [measureAll] answers for, by location; anything absent is zero.
  ///
  /// Keyed rather than positional so a test names the file it means, and so
  /// adding a row to a fixture cannot silently shift every other size by one.
  Map<Uri, StoredImageSize> sizes = <Uri, StoredImageSize>{};

  /// Counts its calls, for the same reason [canReadAllCalls] does: the survey
  /// measures a whole history and must do it in one crossing.
  int measureAllCalls = 0;

  /// Every location handed to [measureAll], flattened across its calls — so a
  /// test can say what was *not* measured, which a call count cannot.
  final List<Uri> measured = <Uri>[];

  /// What [inspectAll] answers, by location; anything absent is intact.
  Map<Uri, StoredImageCondition> conditions = <Uri, StoredImageCondition>{};

  /// Every batch handed to [inspectAll], in call order — so a test can pin
  /// that a large library is inspected in chunks, not one crossing per file.
  final List<List<Uri>> inspectedBatches = <List<Uri>>[];

  @override
  Future<List<StoredImageCondition>> inspectAll(List<Uri> locations) async {
    inspectedBatches.add(List<Uri>.of(locations));
    return <StoredImageCondition>[
      for (final Uri l in locations)
        conditions[l] ?? StoredImageCondition.intact,
    ];
  }

  @override
  Future<List<StoredImageSize>> measureAll(List<Uri> locations) async {
    measureAllCalls++;
    measured.addAll(locations);
    return <StoredImageSize>[
      for (final Uri l in locations) sizes[l] ?? StoredImageSize.zero,
    ];
  }

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

  /// The vault in force, as [setVaultFolder] last left it.
  VaultFolder vault = VaultFolder.standard;

  /// Whether [setVaultFolder] refuses — the platform failure, not a bad label.
  bool vaultWriteFails = false;

  @override
  Future<bool> setVaultFolder(VaultFolder folder) async {
    if (vaultWriteFails) return false;
    vault = folder;
    return true;
  }

  @override
  Future<DownloadLocation> downloadLocation() async => DownloadLocation(
    folder: _granted ?? folder,
    sdCardAvailable: sdCardAvailable,
    vault: vault,
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
