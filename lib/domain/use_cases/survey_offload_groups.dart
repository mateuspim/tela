import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/offload_group.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image_move.dart';
import 'package:tela/domain/models/stored_image_size.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Adds up what is on built-in storage and could be moved to a card.
///
/// Answers the offload screen's only question — *which piles are there, and how
/// much would each free* — as groups that already carry their moves, so the
/// number on screen and the work the button does come from one pass.
///
/// ```dart
/// final List<OffloadGroup> groups = await surveyOffloadGroups();
/// groups.fold(0, (int sum, OffloadGroup g) => sum + g.bytes); // total freed
/// ```
class SurveyOffloadGroups {
  /// Creates the survey over the storage and history seams.
  const SurveyOffloadGroups({
    required ImageStore imageStore,
    required DownloadHistory history,
  }) : _imageStore = imageStore,
       _history = history;

  final ImageStore _imageStore;
  final DownloadHistory _history;

  /// The non-empty groups, in [OffloadKind] order.
  ///
  /// Empty groups are dropped rather than shown at zero: a row saying "Gallery
  /// — 0 files" is a control that cannot be used, and three of them is a screen
  /// that looks broken on a device with nothing to move. An empty list is the
  /// honest "nothing to move here", and the screen says so in one sentence.
  Future<List<OffloadGroup>> call() async {
    final List<DownloadRecord> recorded = await _history.downloads();
    final List<StoredImageSize> sizes = await _imageStore.measureAll(
      <Uri>[for (final DownloadRecord d in recorded) d.location],
    );
    return <OffloadGroup>[
      ..._recordedGroups(recorded, sizes),
      ...await _privateGroup(),
    ];
  }

  /// The two shared-tier groups, split by the tier each row is filed under.
  List<OffloadGroup> _recordedGroups(
    List<DownloadRecord> recorded,
    List<StoredImageSize> sizes,
  ) {
    final Map<OffloadKind, List<StoredImageMove>> moves =
        <OffloadKind, List<StoredImageMove>>{};
    final Map<OffloadKind, int> bytes = <OffloadKind, int>{};
    for (int i = 0; i < recorded.length; i++) {
      final OffloadKind? kind = _kindOf(recorded[i], sizes[i]);
      if (kind == null) continue;
      moves
          .putIfAbsent(kind, () => <StoredImageMove>[])
          .add(
            _moveOf(recorded[i]),
          );
      bytes[kind] = (bytes[kind] ?? 0) + sizes[i].bytes;
    }
    return <OffloadGroup>[
      for (final OffloadKind kind in <OffloadKind>[
        OffloadKind.galleryDownloads,
        OffloadKind.deviceFiles,
      ])
        if (moves[kind] != null)
          OffloadGroup(
            kind: kind,
            moves: moves[kind]!,
            bytes: bytes[kind] ?? 0,
          ),
    ];
  }

  /// Which pile [record] belongs to, or null when it belongs to none.
  ///
  /// Two rows are skipped, and both would otherwise overstate the tally: one
  /// already on a card frees nothing by moving there, and one measuring zero
  /// bytes is a file that could not be opened — deleted from Photos, a revoked
  /// grant — which would also fail the copy. The stale-history sweep is what
  /// removes those; this screen just declines to promise their bytes.
  OffloadKind? _kindOf(DownloadRecord record, StoredImageSize size) {
    if (size.onRemovableVolume || size.bytes == 0) return null;
    return switch (record.tier) {
      StorageTier.sharedGallery => OffloadKind.galleryDownloads,
      StorageTier.filesOutsideGallery => OffloadKind.deviceFiles,
      // Never listed by the history at all; the private group is read from the
      // tier itself below.
      StorageTier.appPrivate => null,
    };
  }

  /// The move a recorded download would make, tag and all.
  ///
  /// The tag rides along because a tag **is** a directory: an offload that
  /// dropped it would flatten a library the user has been filing for months
  /// into one folder on the card, and no undo puts it back.
  StoredImageMove _moveOf(DownloadRecord record) {
    return StoredImageMove(
      ref: record.wallpaper.ref,
      purity: record.wallpaper.purity,
      from: record.tier,
      location: record.location,
      to: StorageTier.filesOutsideGallery,
      tag: record.tag,
    );
  }

  /// The app-private tier as one group, or nothing when it is empty.
  ///
  /// Needs no measuring: the listing already reports each file's size, and the
  /// app-private tier is built-in storage by construction — there is no
  /// app-private directory on a card for a file to already be sitting in.
  Future<List<OffloadGroup>> _privateGroup() async {
    // Only the app-private half, and asked for that way. The library's other
    // home is the vault — images already on the card, in the hidden folder —
    // which are both already where this screen would send them and, worse,
    // would have the copy overwrite the document it is reading;
    // `confirmAndMoveOutOfPrivate` drops them for the same reason. Listing them
    // here and filtering after was the honest version and also the slow one:
    // every card file cost a crossing to be discarded, so the screen took
    // longer the more it had already moved.
    //
    // The filter stays as well as the narrower call. It guards a **copy that
    // deletes its source**, and a guard on that is worth keeping even once the
    // value reaching it is meant to be impossible.
    final List<PrivateImage> images = <PrivateImage>[
      for (final PrivateImage image in await _imageStore.appPrivateImages())
        if (image.tier == StorageTier.appPrivate) image,
    ];
    if (images.isEmpty) return const <OffloadGroup>[];
    return <OffloadGroup>[
      OffloadGroup(
        kind: OffloadKind.privateLibrary,
        moves: <StoredImageMove>[
          for (final PrivateImage image in images)
            StoredImageMove(
              ref: image.ref,
              // Not a claim that it is explicit — a refusal to claim it is
              // not. This tier keeps no record beyond a file name, so the
              // adapter's own gate is what makes the gallery impossible; same
              // reasoning as `confirmAndMoveOutOfPrivate`.
              purity: Purity.nsfw,
              from: StorageTier.appPrivate,
              location: image.location,
              to: StorageTier.filesOutsideGallery,
              tag: image.tag,
            ),
        ],
        bytes: images.fold(
          0,
          (int sum, PrivateImage image) => sum + image.sizeBytes,
        ),
      ),
    ];
  }
}
