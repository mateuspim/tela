import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';

/// How far a bulk delete has got: [done] of [total] settled.
typedef DeletionProgress = void Function(int done, int total);

/// Hard-deletes a batch of downloads — their files and their history rows.
///
/// The bulk sibling of `DeleteDownload`, for the history's multi-select bar.
/// It is not a loop over the single delete: the gallery tier is handed over in
/// one piece so it resolves to one system prompt rather than one per file, then
/// only the rows whose files actually went are forgotten — a declined prompt
/// leaves that subset, files and rows, exactly as they were.
///
/// ```dart
/// final int gone = await deleteDownloads(selected, onProgress: report);
/// ```
class DeleteDownloads {
  /// Creates the use case over the storage and history seams.
  const DeleteDownloads({
    required ImageStore imageStore,
    required DownloadHistory history,
  }) : _imageStore = imageStore,
       _history = history;

  final ImageStore _imageStore;
  final DownloadHistory _history;

  /// How many non-gallery files go to the platform at a time.
  ///
  /// The whole selection used to cross in one call that answered only when the
  /// last file had settled, so clearing a history of hundreds looked frozen —
  /// there was no number to report because nothing came back until it was over
  /// (owner, 2026-07-28). Chunking buys a count to show.
  ///
  /// Twenty, not one: a chunk per file would restore the per-item round trip
  /// this size exists to amortise, and a progress bar that advances in
  /// twentieths of a large selection already reads as continuous motion.
  static const int _chunk = 20;

  /// Deletes every file in [records], forgets the rows that went, and answers
  /// how many actually went — the "3 of 5" the caller reports.
  ///
  /// [onProgress] is called as chunks settle, never on a schedule of its own,
  /// so the count it reports is always a number of files that have genuinely
  /// been dealt with rather than an estimate.
  ///
  /// **The gallery tier goes last, whole.** Its deletes need the OS's own
  /// confirmation, and the platform batches whatever it is given into a single
  /// prompt: splitting them across chunks would ask the user to confirm the
  /// same delete over and over, once per chunk. Everything else is chunked
  /// ahead of it, so the prompt appears after the silent work rather than
  /// interrupting it.
  Future<int> call(
    List<DownloadRecord> records, {
    DeletionProgress? onProgress,
  }) async {
    if (records.isEmpty) return 0;
    final List<DownloadRecord> gallery = <DownloadRecord>[
      for (final DownloadRecord r in records)
        if (r.tier == StorageTier.sharedGallery) r,
    ];
    final List<DownloadRecord> rest = <DownloadRecord>[
      for (final DownloadRecord r in records)
        if (r.tier != StorageTier.sharedGallery) r,
    ];
    final Set<Uri> deleted = <Uri>{};
    for (int at = 0; at < rest.length; at += _chunk) {
      final int end = (at + _chunk).clamp(0, rest.length);
      deleted.addAll(await _deleteFiles(rest.sublist(at, end)));
      onProgress?.call(end, records.length);
    }
    deleted.addAll(await _deleteFiles(gallery));
    onProgress?.call(records.length, records.length);
    await _forgetDeleted(records, deleted);
    return deleted.length;
  }

  Future<Set<Uri>> _deleteFiles(List<DownloadRecord> records) {
    if (records.isEmpty) return Future<Set<Uri>>.value(const <Uri>{});
    return _imageStore.deleteDownloads(<({StorageTier tier, Uri location})>[
      for (final DownloadRecord record in records)
        (tier: record.tier, location: record.location),
    ]);
  }

  /// Forgets every row whose file went, once, at the end.
  ///
  /// Not per chunk: the history write is the cheap half and doing it in one
  /// pass keeps a half-finished delete from leaving rows and files disagreeing
  /// if the batch is interrupted part-way. And not one row at a time either —
  /// [DownloadHistory.forgetAll] takes the whole list in one call, which is
  /// the difference between this and the loop that used to sit here: a
  /// history cleanup of 601 stale rows visibly stalled for seconds on nothing
  /// but round trips (owner, on device, 2026-07-29).
  Future<void> _forgetDeleted(
    List<DownloadRecord> records,
    Set<Uri> deleted,
  ) {
    return _history.forgetAll(<WallpaperRef>[
      for (final DownloadRecord record in records)
        if (deleted.contains(record.location)) record.wallpaper.ref,
    ]);
  }
}
