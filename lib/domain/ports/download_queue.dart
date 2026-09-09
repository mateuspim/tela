import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// The downloads this device still owes, in the order they were asked for.
///
/// A pure-domain port, like `FavoritesRepository`: there is no third-party
/// library behind it to swap, and the fact that its adapter speaks SQL is not
/// something a use case may observe. It is durable rather than in-memory for
/// the one reason the queue exists — a batch of a hundred originals outlives
/// the process that asked for it, and a queue that dies with a stack frame is
/// the bug this replaces.
///
/// **This port does not exclude explicit or app-private downloads, and
/// `DownloadHistory` does.** The two look alike and that difference is the
/// whole point. A history row is a permanent, browsable, backed-up index, which
/// is why an explicit or private download never earns one. A queue entry is a
/// *work list* item that is deleted the moment the file lands — refusing to
/// hold one would not protect anything, it would silently decline to download
/// a wallpaper the user asked for. The privacy rule that still applies is the
/// screen's: the queue UI must not render an explicit entry identifiably on an
/// ungated list.
abstract interface class DownloadQueue {
  /// Everything still owed — pending, running and failed — oldest first.
  Future<List<QueuedDownload>> entries();

  /// Puts every entry still marked running back to pending.
  ///
  /// Call this **once, at startup, before any drain**. `running` is only true
  /// inside the process that claimed it, so an entry wearing it on launch was
  /// claimed by a process that has since died and nothing is downloading it;
  /// left alone it is stranded forever, since [claimNext] only ever takes
  /// pending ones.
  ///
  /// It is a one-shot and not a side effect of [entries] on purpose: demoting
  /// on every read would demote the entries this process has genuinely got in
  /// flight, and [claimNext] would hand the same wallpaper to a second worker.
  Future<void> resumeInterrupted();

  /// Adds [downloads], skipping any wallpaper already queued.
  ///
  /// Idempotent per [WallpaperRef]: re-selecting a wallpaper that is already
  /// waiting must not queue it twice, or a user who ticks the same shelf again
  /// downloads everything on it a second time.
  Future<void> enqueue(List<QueuedDownload> downloads);

  /// Takes the oldest pending entry and marks it running, or answers null when
  /// nothing is pending.
  ///
  /// Atomic, because several workers drain at once: a select followed by a
  /// separate update would let two of them claim — and download — the same
  /// wallpaper.
  Future<QueuedDownload?> claimNext();

  /// Marks [ref] failed for [problem], counting the attempt.
  ///
  /// The entry stays in the queue. Failures are surfaced and retried on the
  /// user's tap, never silently re-tried here: a queue that keeps retrying a
  /// 404 forever is worse than one that says it could not.
  Future<void> markFailed(WallpaperRef ref, ImageStoreProblem problem);

  /// Drops [ref] from the queue — a completed download, or a cancelled one.
  /// A no-op for an entry that is not queued.
  Future<void> remove(WallpaperRef ref);

  /// Puts [ref] back to pending, clearing its failure but keeping its attempt
  /// count. A no-op for an entry that is not queued.
  Future<void> requeue(WallpaperRef ref);

  /// Puts every failed entry back to pending. Answers how many moved.
  Future<int> requeueFailed();

  /// Repoints queued work that explicitly chose [from] to [to].
  ///
  /// Running entries are left alone: their write may already have begun.
  /// Null-tier entries are untouched because they resolve the configured
  /// destination when claimed.
  Future<int> reroute(StorageTier from, StorageTier to);

  /// Empties the queue. Nothing already written to disk is touched — this
  /// cancels what is owed, it does not delete what landed.
  Future<void> clear();
}
