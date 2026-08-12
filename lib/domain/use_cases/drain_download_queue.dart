import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/ports/download_queue.dart';
import 'package:tela/domain/use_cases/download_wallpaper.dart';

/// Whether the user has paused the queue, asked before every claim.
///
/// A callback rather than a flag, because pausing must take effect part-way
/// through a drain: a `bool` read once at the start would keep downloading the
/// remaining ninety wallpapers after the user tapped Pause.
typedef DownloadQueuePaused = bool Function();

/// Called after each entry settles, so the caller can re-read the queue.
typedef DownloadSettled = Future<void> Function();

/// Empties the download queue, several at a time.
///
/// UI-free on purpose, so the whole draining rule is plain-Dart testable and so
/// the same worker can later be driven by something with no screen at all.
///
/// ```dart
/// await drainDownloadQueue(paused: () => false, onSettled: refresh);
/// ```
class DrainDownloadQueue {
  /// Creates the worker over the queue and the download it performs.
  const DrainDownloadQueue({
    required DownloadQueue queue,
    required PerformDownload perform,
    int maxConcurrent = _defaultConcurrency,
  }) : _queue = queue,
       _perform = perform,
       _maxConcurrent = maxConcurrent;

  /// Three at once.
  ///
  /// One is what the old sequential batch did, and it left the connection idle
  /// between multi-megabyte originals. Twenty would hold twenty of them in
  /// flight for a wall the user selected in two seconds, and on the native side
  /// they all queue behind `MainActivity.downloadExecutor` anyway, which is
  /// sized to match this. Three saturates a phone connection without either.
  static const int _defaultConcurrency = 3;

  final DownloadQueue _queue;
  final PerformDownload _perform;
  final int _maxConcurrent;

  /// Drains until the queue is empty or [paused] answers true.
  ///
  /// Runs [_maxConcurrent] independent worker loops rather than batching:
  /// batches move at the speed of their slowest member, and a queue of a
  /// hundred wallpapers of wildly different sizes would spend most of it
  /// waiting on one 20MB original with two slots idle.
  ///
  /// Callers must not run two drains at once — [DownloadQueue.claimNext] keeps
  /// that safe rather than correct, and a second drain only adds slots the
  /// concurrency cap was chosen to prevent.
  Future<void> call({
    required DownloadQueuePaused paused,
    required DownloadSettled onSettled,
  }) async {
    await Future.wait(<Future<void>>[
      for (int slot = 0; slot < _maxConcurrent; slot++)
        _drainSlot(paused, onSettled),
    ]);
  }

  /// One worker loop: claim, download, repeat until there is nothing left.
  Future<void> _drainSlot(
    DownloadQueuePaused paused,
    DownloadSettled onSettled,
  ) async {
    while (!paused()) {
      final QueuedDownload? next = await _queue.claimNext();
      if (next == null) return;
      await _settle(next, onSettled);
    }
  }

  /// Downloads [item], then takes it out of the queue or marks why it stayed.
  ///
  /// **[ImageStoreProblem.notConfigured] is a failure here, not a prompt.**
  /// `ConfiguredDownload` answers it by opening the volume chooser and
  /// retrying, which a worker that may be draining with no screen mounted
  /// cannot do. A batch resolves its destination before it enqueues, so an
  /// entry that still hits this needs the user, and telling them is the only
  /// honest thing left to do with it.
  Future<void> _settle(QueuedDownload item, DownloadSettled onSettled) async {
    try {
      await _perform(item.wallpaper, tier: item.tier, tag: item.tag);
      await _queue.remove(item.ref);
    } on ImageStoreFailure catch (failure) {
      await _queue.markFailed(item.ref, failure.problem);
    } on Exception {
      await _queue.markFailed(item.ref, ImageStoreProblem.unknown);
    }
    await onSettled();
  }
}
