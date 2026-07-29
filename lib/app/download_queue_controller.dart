import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_queue.dart';
import 'package:tela/features/private_library/private_unlock_session.dart';

/// Whether the user has paused the queue.
///
/// Its own provider rather than a field on [DownloadQueueController], so the
/// Pause button rebuilds on a toggle without the whole entry list being
/// republished — the same split `PrivateUnlockSession` uses for the app-lock.
///
/// **In memory, never persisted.** A killed app is not a paused app: persisting
/// this would mean one crash leaves a queue that silently never drains again,
/// and the user's only clue would be downloads that never arrive.
final NotifierProvider<DownloadQueuePause, bool> downloadQueuePausedProvider =
    NotifierProvider<DownloadQueuePause, bool>(DownloadQueuePause.new);

/// Holds the paused flag. Toggled only through [DownloadQueueController], which
/// also has to restart the drain.
class DownloadQueuePause extends Notifier<bool> {
  @override
  bool build() => false;

  /// Stops the queue claiming anything new.
  void hold() => state = true;

  /// Clears the pause. Does not itself drain — see
  /// [DownloadQueueController.resume], which has to restart the worker too.
  void release() => state = false;
}

/// The downloads still owed, and the worker emptying them.
///
/// Owns and emits its own state rather than being an invalidated
/// `FutureProvider`: the queue mutates several times a second while its screen
/// is open, and the caching a plain future does for the process lifetime is
/// exactly the staleness `refreshDownloads` exists to undo (see
/// `library_listings.dart`). Non-autoDispose, because it must keep draining
/// after the queue screen is closed.
final AsyncNotifierProvider<DownloadQueueController, List<QueuedDownload>>
downloadQueueControllerProvider =
    AsyncNotifierProvider<DownloadQueueController, List<QueuedDownload>>(
      DownloadQueueController.new,
    );

/// Enqueues downloads, drains them, and reports where each one got to.
class DownloadQueueController extends AsyncNotifier<List<QueuedDownload>> {
  bool _draining = false;
  bool _disposed = false;

  @override
  Future<List<QueuedDownload>> build() async {
    ref.onDispose(() => _disposed = true);
    final DownloadQueue queue = ref.read(downloadQueueProvider);
    // Entries a killed process left marked running are not running. Demote them
    // before anything reads or claims, or they are stranded forever.
    await queue.resumeInterrupted();
    final List<QueuedDownload> entries = await queue.entries();
    if (entries.isNotEmpty) _startDrain();
    return entries;
  }

  /// Adds [wallpapers] to the queue and starts draining.
  ///
  /// [tier] is the per-download override the batch chooser resolved, forwarded
  /// untouched; null means "resolve it when the entry runs", which is what a
  /// pin-governed batch wants.
  ///
  /// Answers how many were newly queued — a wallpaper already waiting is not
  /// counted, so "queued 12" never claims more than it did.
  Future<int> enqueue(
    List<Wallpaper> wallpapers, {
    StorageTier? tier,
  }) async {
    final DownloadQueue queue = ref.read(downloadQueueProvider);
    final Set<WallpaperRef> before = await _queuedRefs(queue);
    // One stamp per entry, strictly increasing. `DateTime.now()` does not
    // advance between the hundred iterations of this loop, and the queue is
    // ordered by it — tied timestamps would let SQLite return the line in an
    // arbitrary order, which is not the order the user ticked.
    final DateTime start = DateTime.now();
    await queue.enqueue(<QueuedDownload>[
      for (final (int index, Wallpaper wallpaper) in wallpapers.indexed)
        QueuedDownload(
          wallpaper: wallpaper,
          tier: tier,
          queuedAt: start.add(Duration(microseconds: index)),
        ),
    ]);
    await _republish();
    _startDrain();
    return wallpapers.where((Wallpaper w) => !before.contains(w.ref)).length;
  }

  /// Stops claiming new entries. Anything already in flight finishes — a
  /// half-written file is worse than one more download.
  void pause() => ref.read(downloadQueuePausedProvider.notifier).hold();

  /// Clears the pause and picks the queue back up.
  void resume() {
    ref.read(downloadQueuePausedProvider.notifier).release();
    _startDrain();
  }

  /// Puts one failed entry back in line and starts draining.
  Future<void> retry(WallpaperRef entry) async {
    await ref.read(downloadQueueProvider).requeue(entry);
    await _republish();
    _startDrain();
  }

  /// Puts every failed entry back in line. Answers how many moved.
  Future<int> retryFailed() async {
    final int moved = await ref.read(downloadQueueProvider).requeueFailed();
    await _republish();
    _startDrain();
    return moved;
  }

  /// Drops one entry. A download already in flight still finishes and still
  /// lands — cancelling takes it out of the line, it cannot unwrite a file.
  Future<void> cancel(WallpaperRef entry) async {
    await ref.read(downloadQueueProvider).remove(entry);
    await _republish();
  }

  /// Empties the queue. Nothing already downloaded is touched.
  Future<void> cancelAll() async {
    await ref.read(downloadQueueProvider).clear();
    await _republish();
  }

  /// Runs the worker unless one is already running.
  ///
  /// The guard is the whole reason this is not just a call: a second drain
  /// would add three more slots to the three the concurrency cap allows, and
  /// every enqueue, retry and resume calls in here.
  void _startDrain() {
    if (_draining || _disposed) return;
    if (ref.read(downloadQueuePausedProvider)) return;
    _draining = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    // Yields past this turn of the event loop before touching anything. A drain
    // kicked off from [build] must not publish state while build is still
    // running, and a fake queue whose futures complete immediately would
    // otherwise do exactly that.
    await Future<void>.delayed(Duration.zero);
    // The container can go during that gap — a disposed process on the way out
    // is the ordinary case — and reading a Ref past disposal throws.
    if (_disposed) return;
    try {
      await ref.read(drainDownloadQueueProvider)(
        paused: () => _disposed || ref.read(downloadQueuePausedProvider),
        onSettled: _onSettled,
      );
    } finally {
      _draining = false;
    }
  }

  /// After each entry lands or fails: republish the queue, and re-read the
  /// listings the new file belongs in so the History tab fills behind the
  /// Queue tab rather than on the next launch.
  Future<void> _onSettled() async {
    await _republish();
    if (!_disposed) refreshDownloadsFrom(ref);
  }

  Future<void> _republish() async {
    if (_disposed) return;
    final List<QueuedDownload> entries = await ref
        .read(downloadQueueProvider)
        .entries();
    if (_disposed) return;
    state = AsyncData<List<QueuedDownload>>(entries);
  }

  Future<Set<WallpaperRef>> _queuedRefs(DownloadQueue queue) async {
    final List<QueuedDownload> entries = await queue.entries();
    return <WallpaperRef>{
      for (final QueuedDownload entry in entries) entry.ref,
    };
  }
}

/// Whether the queue tab may identify an explicit entry.
///
/// Lives here, at the composition root, because it joins two features: the
/// queue screen asks it and the private library answers it, and features may
/// not import each other (CLAUDE.md). The queue tab sits behind no app-lock and
/// no `FLAG_SECURE`, so an explicit entry shows a neutral row until the private
/// library's unlock has been paid this foreground session — after which the
/// owner has already proved who they are and hiding it only makes the queue
/// harder to read.
final Provider<bool> queueRevealsPrivateProvider = Provider<bool>(
  (Ref ref) => ref.watch(privateUnlockSessionProvider),
);

/// How many entries in [entries] are still owed — pending or running.
///
/// A top-level function rather than a getter on the controller so the queue
/// header can compute it from a plain list, including in a widget test that
/// never builds the controller.
int owedDownloads(List<QueuedDownload> entries) {
  return entries
      .where((QueuedDownload e) => e.state != DownloadQueueState.failed)
      .length;
}

/// How many entries in [entries] failed and are waiting on the user.
int failedDownloads(List<QueuedDownload> entries) {
  return entries
      .where((QueuedDownload e) => e.state == DownloadQueueState.failed)
      .length;
}
