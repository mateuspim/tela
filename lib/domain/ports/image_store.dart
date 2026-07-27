import 'package:tela/domain/models/download_deletion.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';
import 'package:tela/domain/models/stored_image.dart';

/// Stores a remote wallpaper using a user-selected storage tier.
///
/// Implementations enforce purity restrictions themselves; features must never
/// decide whether a destination is safe for an image.
abstract interface class ImageStore {
  /// Downloads and persists one image.
  ///
  /// [source] and [id] together name the file on disk (`wallhaven-e7jvjd.jpg`),
  /// which is why the source is a parameter and not an afterthought: the
  /// app-private tier is listed back off those names alone, so a file stored
  /// without its source is a file whose origin is gone. Take them from
  /// `Wallpaper.ref` rather than composing the pair by hand.
  ///
  /// Throws a safe `ImageStoreFailure`, never one containing [imageUrl] or a
  /// private local path.
  Future<StoredImage> store({
    required SourceId source,
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

  /// Hard-deletes a downloaded file from its storage [tier] — the one action
  /// that reaches the file itself, not just an index of it.
  ///
  /// This is the loud counterpart to `DownloadHistory.forget`, which only drops
  /// a list row. Routing is by tier: the app-private file tela owns, the SAF
  /// document under the user's granted tree, or the MediaStore image. That last
  /// case is why this can return without deleting: on Android 30+ a gallery
  /// delete goes through the system's own confirmation, which the user may
  /// dismiss — a [DownloadDeletion.declined], not a failure.
  ///
  /// [location] is the tier's own URI (a `file:`, document, or MediaStore URI),
  /// exactly as [StoredImage.location] and [PrivateImage.location] carry it.
  ///
  /// Throws a safe `ImageStoreFailure` for a delete that was meant to happen
  /// and could not; never one containing the path.
  Future<DownloadDeletion> deleteDownload({
    required StorageTier tier,
    required Uri location,
  });

  /// Hard-deletes several downloads at once, and reports which files went.
  ///
  /// The bulk counterpart to [deleteDownload], and the reason it is not just a
  /// loop over it: the gallery tier's system confirmation takes a *collection*,
  /// so a whole selection of gallery downloads is one OS prompt rather than one
  /// per file. The files and SAF documents delete individually; the gallery
  /// items ride that single prompt, all-or-nothing.
  ///
  /// Returns the locations actually deleted — a subset of the requested ones
  /// when some failed or the user declined the gallery prompt — so the caller
  /// forgets exactly those rows and no others. Never throws for a partial
  /// result; an empty set is an ordinary "nothing went" outcome.
  Future<Set<Uri>> deleteDownloads(
    List<({StorageTier tier, Uri location})> targets,
  );

  /// Whether the platform shows its own confirmation for a gallery-tier delete.
  ///
  /// True on Android 30+, where `MediaStore.createDeleteRequest` is mandatory
  /// and puts a system "allow tela to delete?" prompt in front of every gallery
  /// delete. The UI reads this to avoid stacking tela's own confirmation on top
  /// of the OS one — and, just as importantly, to keep tela's confirmation on
  /// the older path (API 29) where a gallery delete is silent and tela's dialog
  /// is the *only* thing standing between a tap and a lost file.
  Future<bool> galleryDeleteConfirmedBySystem();

  /// Whether the file at [location] can still be opened.
  ///
  /// A download tela wrote is not a download tela keeps: a gallery image can be
  /// deleted from Photos and a document one from a file manager, and tela hears
  /// about neither. The download history is what asks — it calls itself
  /// "wallpapers already on this device", and a row whose file is gone makes
  /// that a lie until the tile says otherwise.
  ///
  /// Answers false rather than throwing, for every reason a file might not
  /// open: gone, revoked, unreadable. "I could not open it" is the only fact
  /// the caller wants, and none of the ways to fail are worth distinguishing.
  Future<bool> canRead(Uri location);

  /// Where files-outside-gallery writes, and whether a card is offered.
  ///
  /// Never throws for the ordinary "nothing chosen yet" state — that is a
  /// [DownloadLocation] with a null folder, not an error. A card being present
  /// is reported the same whether or not a folder exists, so the picker can
  /// offer it before anything is configured.
  Future<DownloadLocation> downloadLocation();

  /// Opens the system folder picker pointed at [kind]'s volume and remembers
  /// what the user grants.
  ///
  /// Returns the new folder, or null when they backed out or the volume was
  /// gone (a card asked for with an empty slot) — a cancelled picker must leave
  /// the previous grant exactly as it was.
  Future<DownloadFolder?> chooseDownloadFolder(StorageVolumeKind kind);
}
