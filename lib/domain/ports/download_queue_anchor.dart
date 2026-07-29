/// Keeps the OS from reclaiming tela while the download queue still owes files.
///
/// A port, so the platform mechanism behind it — an Android foreground service
/// — lives in one adapter and nothing above it knows the word "service".
///
/// **It does not drain anything.** The draining rule stays where it is, in
/// `DrainDownloadQueue`, and this only says *when it matters that the process
/// stays alive*. A batch of a hundred originals is an ordinary low-memory-kill
/// candidate the moment the user switches away — which is the exact user who
/// started it and left it running.
///
/// ```dart
/// await anchor.hold(
///   title: l10n.downloadQueueNoticeTitle,
///   body: l10n.downloadQueueNoticeBody(7),
/// );
/// await anchor.release(); // the queue is empty, or paused
/// ```
abstract interface class DownloadQueueAnchor {
  /// Asks the platform to keep tela alive, showing [title] and [body].
  ///
  /// Called again with new words to update them, so one call covers both
  /// raising the anchor and reporting how much is left.
  ///
  /// Answers whether the anchor is actually up. **False is not an error and
  /// needs no message**: the platform can refuse — Android forbids starting a
  /// foreground service from the background — and a refused anchor leaves the
  /// drain running, merely killable, which is where it stood before this port
  /// existed. Callers must not treat it as a failed download.
  Future<bool> hold({required String title, required String body});

  /// Drops the anchor. A no-op when none is held.
  Future<void> release();
}
