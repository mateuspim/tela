import 'package:tela/domain/models/download_deletion.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
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
  /// [tag] is the folder **inside** that tier the image is filed under, or null
  /// for the tier's own root. It never influences which tier is used: the
  /// purity rules above have already decided that, and a tag choosing a
  /// destination would be a way around them.
  ///
  /// Storing a wallpaper this tier already holds under a *different* tag moves
  /// it rather than duplicating it — one wallpaper, one tag — which is the same
  /// rule that makes re-downloading one overwrite it instead of leaving a
  /// second copy beside it. Read [StoredImage.tag] for where it actually ended
  /// up.
  ///
  /// Throws a safe `ImageStoreFailure`, never one containing [imageUrl] or a
  /// private local path.
  Future<StoredImage> store({
    required SourceId source,
    required String id,
    required String imageUrl,
    required Purity purity,
    required StorageTier tier,
    TagFolder? tag,
  });

  /// Copies an image **already on this device** into [tier], under the same
  /// `source-id` name [store] would give it.
  ///
  /// The local-source twin of [store], which can only fetch. It exists so a
  /// download can change tier without the network: the bytes are already here,
  /// and re-fetching several megabytes tela wrote itself is both slow and needs
  /// a connection the user may not have — the same argument that made a past
  /// download re-appliable from its own file.
  ///
  /// [from] is the current location in whatever tier holds it — a MediaStore
  /// URI, a SAF document, or a local file — and reading all three is the
  /// adapter's problem, not the caller's.
  ///
  /// **This copies; it does not move.** Deleting the original is
  /// [deleteDownloads]' job, and keeping the two apart is what lets a caller
  /// undo the copy when the delete is declined.
  ///
  /// Enforces the same purity rules [store] does, from the same place — so an
  /// image whose purity is unknown, and therefore given as `nsfw`, can never be
  /// copied into the gallery whatever the caller asks for.
  ///
  /// Throws a safe `ImageStoreFailure`, never one naming [from] or the result.
  Future<StoredImage> copyStoredImage({
    required SourceId source,
    required String id,
    required Uri from,
    required Purity purity,
    required StorageTier tier,
    TagFolder? tag,
  });

  /// Moves an image already in [tier] into [tag]'s folder, **without copying**.
  ///
  /// The cheap way to change a download's tag, and the reason it exists beside
  /// `MoveStoredImages`: nothing here moves a byte, and nothing raises the
  /// system delete confirmation that a copy-then-delete must on Android 30+.
  /// Retagging a selection of thirty is thirty metadata updates rather than
  /// thirty megabytes and a prompt.
  ///
  /// **Within one tier only, which is a safety property rather than a
  /// limitation.** A tag picks a directory inside a destination the purity
  /// rules have already approved; changing tiers is [store] and
  /// [copyStoredImage]'s business, where that gate lives. Nothing here can put
  /// an explicit image in the gallery, because nothing here changes tiers.
  ///
  /// A null [tag] moves the image back to the tier root — "no tag" is a
  /// destination, not a refusal to act.
  ///
  /// Answers the image's **new** location, which the caller must store: two of
  /// the three tiers change their URI, and a history row still naming the old
  /// one describes a file that is not there.
  ///
  /// Throws a safe `ImageStoreFailure` when the move could not happen at all —
  /// a file this install no longer owns, a provider that refuses — so the
  /// caller can fall back to copy-then-delete.
  Future<StoredImage> retagStoredImage({
    required StorageTier tier,
    required Uri location,
    required TagFolder? tag,
  });

  /// The whole private library, most recently saved first — **both homes**.
  ///
  /// The app-private tier and the hidden vault on the files tier. Neither is
  /// visible to anything but tela — one is app-internal, the other a
  /// dot-prefixed folder no file manager shows and no index reaches — so
  /// without this they are write-only. Each row says which home it came from,
  /// because that routes its delete.
  ///
  /// Costs a walk of both, which on a card is a per-file crossing. A caller
  /// that only wants built-in storage should ask [appPrivateImages] instead.
  Future<List<PrivateImage>> privateImages();

  /// The app-private tier alone, most recently saved first.
  ///
  /// Same rows as [privateImages], minus the vault — for the caller whose
  /// question is *what is still on built-in storage*, which is one the files
  /// already on a card cannot be part of the answer to. Reading them only to
  /// drop them is what made the offload screen slower the more it had moved.
  Future<List<PrivateImage>> appPrivateImages();

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

  /// Which of [locations] can still be opened, answered in one crossing.
  ///
  /// The bulk sibling of [canRead], and it exists for a reason a loop cannot
  /// solve: the download history probes **every** row it shows, so a library of
  /// hundreds asked hundreds of separate questions, each a platform round trip
  /// that queued behind the last on a single native thread. The badges took
  /// long enough to arrive that the screen looked broken (owner, 2026-07-28).
  ///
  /// The order of the answers matches the order of [locations], so a caller can
  /// pair them by index. A location that cannot be opened — gone, revoked,
  /// unreadable — is false, exactly as in [canRead]; nothing here throws for a
  /// single bad entry, because one unreadable file must not cost the caller
  /// every other answer in the batch.
  Future<List<bool>> canReadAll(List<Uri> locations);

  /// How big each of [locations] is, and whether it already sits on a card.
  ///
  /// The sibling of [canReadAll], batched for the same reason and answered in
  /// the same order, so a caller pairs the results with its rows by index. It
  /// exists because a download row records no size: the wallpaper's *reported*
  /// bytes come from the source's listing and describe the original file, not
  /// the one on this disk, and a screen promising freed space has to weigh what
  /// is actually there.
  ///
  /// A file that cannot be measured — deleted from Photos, a revoked grant —
  /// is [StoredImageSize.zero], never an exception and never a shorter list.
  Future<List<StoredImageSize>> measureAll(List<Uri> locations);

  /// Whether each of [locations] looks whole, answered in one crossing.
  ///
  /// The sibling of [measureAll], batched and ordered the same way. Reads only
  /// each file's size and two ends — an empty file, or one missing its format's
  /// end marker, is damaged — so a whole library is inspected in seconds.
  ///
  /// A file that cannot be opened is [StoredImageCondition.unreadable], never
  /// an exception and never a shorter list; so is every row of a reply that
  /// could not be read. Unknown is never reported as broken.
  ///
  /// ```dart
  /// final List<StoredImageCondition> found = await store.inspectAll(uris);
  /// ```
  Future<List<StoredImageCondition>> inspectAll(List<Uri> locations);

  /// Where files-outside-gallery writes, and whether a card is offered.
  ///
  /// Never throws for the ordinary "nothing chosen yet" state — that is a
  /// [DownloadLocation] with a null folder, not an error. A card being present
  /// is reported the same whether or not a folder exists, so the picker can
  /// offer it before anything is configured.
  Future<DownloadLocation> downloadLocation();

  /// Renames the hidden folder explicit downloads land in, from now on.
  ///
  /// **Renames nothing on disk.** The old directory keeps what is in it and
  /// the app keeps reading both, because moving a folder full of images
  /// because a text field lost focus is not a rename — it is a migration, and
  /// a failed one would strand the library across two directories with no
  /// record of which half went where. The settings row says so in its own
  /// words.
  ///
  /// Answers false when the platform refused the label. Callers validate with
  /// [VaultFolder] first, so a false here is a storage failure rather than a
  /// typo, and there is nothing for the user to correct.
  Future<bool> setVaultFolder(VaultFolder vault);

  /// Opens the system folder picker pointed at [kind]'s volume and remembers
  /// what the user grants as the folder for [purity]'s bucket — explicit
  /// downloads have their own (see `DownloadLocation.explicitFolder`).
  ///
  /// Returns the new folder, or null when they backed out or the volume was
  /// gone (a card asked for with an empty slot) — a cancelled picker must leave
  /// the previous grant exactly as it was.
  ///
  /// ```dart
  /// await store.chooseDownloadFolder(
  ///   StorageVolumeKind.sdCard,
  ///   purity: Purity.nsfw,
  /// );
  /// ```
  Future<DownloadFolder?> chooseDownloadFolder(
    StorageVolumeKind kind, {
    required Purity purity,
  });
}
