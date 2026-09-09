import 'package:drift/drift.dart';
import 'package:tela/data/db/stored_wallpaper_fields.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_queue.dart';

/// Keeps the download queue as whole wallpaper rows in tela's database.
///
/// Durable rather than in-memory is the entire point: a batch of a hundred
/// originals outlives the process that asked for it, and the queue this
/// replaces was a `for` loop's stack frame.
///
/// ```dart
/// final DownloadQueue queue = DriftDownloadQueue(db);
/// await queue.enqueue(<QueuedDownload>[entry]);
/// ```
class DriftDownloadQueue implements DownloadQueue {
  /// Creates the adapter over an open [TelaDatabase].
  const DriftDownloadQueue(this._db);

  final TelaDatabase _db;

  @override
  Future<List<QueuedDownload>> entries() async {
    final List<QueueRow> rows = await _db.queueRows();
    return rows.map(_toQueued).toList();
  }

  @override
  Future<void> resumeInterrupted() async {
    await _db.moveQueueEntries(
      DownloadQueueState.running.name,
      DownloadQueueState.pending.name,
    );
  }

  @override
  Future<void> enqueue(List<QueuedDownload> downloads) async {
    for (final QueuedDownload download in downloads) {
      await _db.addQueueEntry(_toRow(download));
    }
  }

  @override
  Future<QueuedDownload?> claimNext() async {
    final QueueRow? claimed = await _db.claimNextQueueRow(
      DownloadQueueState.pending.name,
      DownloadQueueState.running.name,
    );
    return claimed == null ? null : _toQueued(claimed);
  }

  @override
  Future<void> markFailed(WallpaperRef ref, ImageStoreProblem problem) {
    return _db.failQueueEntry(
      ref,
      DownloadQueueState.failed.name,
      problem.name,
    );
  }

  @override
  Future<void> remove(WallpaperRef ref) => _db.deleteQueueEntry(ref);

  @override
  Future<void> requeue(WallpaperRef ref) {
    return _db.requeueQueueEntry(ref, DownloadQueueState.pending.name);
  }

  @override
  Future<int> requeueFailed() {
    return _db.moveQueueEntries(
      DownloadQueueState.failed.name,
      DownloadQueueState.pending.name,
    );
  }

  @override
  Future<int> reroute(StorageTier from, StorageTier to) {
    return _db.rerouteQueueEntries(
      from.name,
      to.name,
      DownloadQueueState.running.name,
    );
  }

  @override
  Future<void> clear() => _db.clearQueue();

  DownloadQueueEntriesCompanion _toRow(QueuedDownload download) {
    final Wallpaper wallpaper = download.wallpaper;
    return DownloadQueueEntriesCompanion.insert(
      source: wallpaper.source.value,
      id: wallpaper.id,
      pageUrl: wallpaper.pageUrl.toString(),
      fullImageUrl: wallpaper.fullImageUrl,
      thumbSmallUrl: wallpaper.thumbSmallUrl,
      thumbLargeUrl: wallpaper.thumbLargeUrl,
      thumbOriginalUrl: wallpaper.thumbOriginalUrl,
      width: wallpaper.resolution.width,
      height: wallpaper.resolution.height,
      fileSizeBytes: wallpaper.fileSizeBytes,
      purity: wallpaper.purity.name,
      category: storableCategory(wallpaper.category),
      colors: joinedColors(wallpaper.colors),
      tier: Value<String?>(download.tier?.name),
      tag: Value<String?>(download.tag?.name),
      state: download.state.name,
      attempts: Value<int>(download.attempts),
      failure: Value<String?>(download.failure?.name),
      queuedAt: download.queuedAt,
    );
  }

  QueuedDownload _toQueued(QueueRow row) {
    return QueuedDownload(
      wallpaper: _toWallpaper(row),
      tier: row.tier == null ? null : storedTier(row.tier!),
      tag: storedTag(row.tag),
      state: _storedState(row.state),
      attempts: row.attempts,
      failure: row.failure == null ? null : _storedProblem(row.failure!),
      queuedAt: row.queuedAt,
    );
  }

  /// Reads a stored state, treating an unrecognised one as
  /// [DownloadQueueState.pending].
  ///
  /// Fails towards *doing the work*: a corrupt cell read as pending costs one
  /// retry of a download the user asked for, where reading it as failed or
  /// running would silently strand it in the queue forever.
  DownloadQueueState _storedState(String stored) {
    return DownloadQueueState.values
            .where((DownloadQueueState state) => state.name == stored)
            .firstOrNull ??
        DownloadQueueState.pending;
  }

  /// Reads a stored failure reason, falling back to
  /// [ImageStoreProblem.unknown] — the row already says it failed, and an
  /// unreadable reason must not turn that into a success.
  ImageStoreProblem _storedProblem(String stored) {
    return ImageStoreProblem.values
            .where((ImageStoreProblem problem) => problem.name == stored)
            .firstOrNull ??
        ImageStoreProblem.unknown;
  }

  Wallpaper _toWallpaper(QueueRow row) {
    return Wallpaper(
      id: row.id,
      source: storedSource(row.source),
      pageUrl: Uri.parse(row.pageUrl),
      fullImageUrl: row.fullImageUrl,
      thumbSmallUrl: row.thumbSmallUrl,
      thumbLargeUrl: row.thumbLargeUrl,
      thumbOriginalUrl: row.thumbOriginalUrl,
      resolution: Resolution(row.width, row.height),
      fileSizeBytes: row.fileSizeBytes,
      purity: storedPurity(row.purity),
      category: storedCategory(row.category),
      colors: storedColors(row.colors),
    );
  }
}
