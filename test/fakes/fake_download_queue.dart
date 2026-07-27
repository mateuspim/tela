import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_queue.dart';

/// In-memory [DownloadQueue], oldest entry first.
///
/// Holds explicit and app-private entries without complaint, exactly as the
/// port requires: the queue is a work list, and it is `DownloadHistory` — not
/// this — that refuses to index those. The Drift adapter has its own test for
/// its own ordering and state transitions.
class FakeDownloadQueue implements DownloadQueue {
  /// Creates a fake holding [initial], oldest first.
  FakeDownloadQueue({List<QueuedDownload> initial = const <QueuedDownload>[]})
    : _entries = List<QueuedDownload>.of(initial);

  final List<QueuedDownload> _entries;

  /// How many times [resumeInterrupted] has been called, so a test can prove
  /// the startup demotion happens exactly once and before any claim.
  int resumes = 0;

  @override
  Future<List<QueuedDownload>> entries() async =>
      List<QueuedDownload>.of(_entries);

  @override
  Future<void> resumeInterrupted() async {
    resumes++;
    _replaceAll(
      (QueuedDownload entry) => entry.state == DownloadQueueState.running
          ? _at(entry, DownloadQueueState.pending)
          : entry,
    );
  }

  @override
  Future<void> enqueue(List<QueuedDownload> downloads) async {
    for (final QueuedDownload download in downloads) {
      if (_indexOf(download.ref) != -1) continue;
      _entries.add(download);
    }
  }

  @override
  Future<QueuedDownload?> claimNext() async {
    final int index = _entries.indexWhere(
      (QueuedDownload entry) => entry.state == DownloadQueueState.pending,
    );
    if (index == -1) return null;
    final QueuedDownload claimed = QueuedDownload(
      wallpaper: _entries[index].wallpaper,
      queuedAt: _entries[index].queuedAt,
      tier: _entries[index].tier,
      state: DownloadQueueState.running,
      attempts: _entries[index].attempts + 1,
    );
    _entries[index] = claimed;
    return claimed;
  }

  @override
  Future<void> markFailed(WallpaperRef ref, ImageStoreProblem problem) async {
    final int index = _indexOf(ref);
    if (index == -1) return;
    _entries[index] = _at(
      _entries[index],
      DownloadQueueState.failed,
      failure: problem,
    );
  }

  @override
  Future<void> remove(WallpaperRef ref) async {
    _entries.removeWhere((QueuedDownload entry) => entry.ref == ref);
  }

  @override
  Future<void> requeue(WallpaperRef ref) async {
    final int index = _indexOf(ref);
    if (index == -1) return;
    _entries[index] = _at(_entries[index], DownloadQueueState.pending);
  }

  @override
  Future<int> requeueFailed() async {
    final int failed = _entries
        .where((QueuedDownload e) => e.state == DownloadQueueState.failed)
        .length;
    _replaceAll(
      (QueuedDownload entry) => entry.state == DownloadQueueState.failed
          ? _at(entry, DownloadQueueState.pending)
          : entry,
    );
    return failed;
  }

  @override
  Future<void> clear() async => _entries.clear();

  int _indexOf(WallpaperRef ref) =>
      _entries.indexWhere((QueuedDownload entry) => entry.ref == ref);

  void _replaceAll(QueuedDownload Function(QueuedDownload) transform) {
    final List<QueuedDownload> mapped = _entries.map(transform).toList();
    _entries
      ..clear()
      ..addAll(mapped);
  }

  /// [entry] in [state], clearing its failure unless a new one is given —
  /// the same rule the Drift adapter's requeue follows.
  QueuedDownload _at(
    QueuedDownload entry,
    DownloadQueueState state, {
    ImageStoreProblem? failure,
  }) {
    return QueuedDownload(
      wallpaper: entry.wallpaper,
      queuedAt: entry.queuedAt,
      tier: entry.tier,
      state: state,
      attempts: entry.attempts,
      failure: failure,
    );
  }
}
