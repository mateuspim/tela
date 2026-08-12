import 'package:meta/meta.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

/// Where one queued download has got to.
///
/// There is deliberately no `done`. A finished download's record is its history
/// row (or, for a private one, the file itself); a second completed list here
/// would be a second index of the same fact, free to disagree with the first.
/// A settled item leaves the queue.
enum DownloadQueueState {
  /// Waiting for a free slot.
  pending,

  /// In flight right now.
  ///
  /// Only true within the process that claimed it. A row still marked this way
  /// when the queue is next opened was claimed by a process that has since
  /// died, and the adapter demotes it back to [pending] rather than believing
  /// a download is running that nothing is running.
  running,

  /// Tried and did not land. Stays in the queue until retried or cancelled —
  /// a failure the user never sees is a download they think they have.
  failed,
}

/// One wallpaper waiting to be downloaded, and how that has gone so far.
///
/// Carries the whole [Wallpaper] for the same reason `DownloadRecord` does: the
/// queue must render and drain with no listing behind it, including on the
/// launch after the process that filled it was killed.
///
/// ```dart
/// final QueuedDownload item = QueuedDownload(
///   wallpaper: wallpaper,
///   queuedAt: DateTime.now(),
/// );
/// ```
@immutable
class QueuedDownload {
  /// Creates a queue entry, pending and untried unless told otherwise.
  const QueuedDownload({
    required this.wallpaper,
    required this.queuedAt,
    this.tier,
    this.tag,
    this.state = DownloadQueueState.pending,
    this.attempts = 0,
    this.failure,
  });

  /// What to download, whole.
  final Wallpaper wallpaper;

  /// The per-download destination override, or null to resolve it when the
  /// item actually runs.
  ///
  /// Null is not "unknown" — it is the ordinary case, and it is what a
  /// pin-governed batch enqueues on purpose. `DownloadWallpaper` resolves a
  /// null tier through the pin and the purity's configured destination, so a
  /// queue that outlives a settings change lands where the user last said,
  /// not where they said when they tapped.
  final StorageTier? tier;

  /// The tag folder this download will be filed under, or null for none.
  ///
  /// Unlike [tier], null here means null: a tag is answered once, in the
  /// chooser, and there is nothing to resolve later — no pin and no per-purity
  /// default stands behind it. An entry queued without one lands untagged
  /// however the settings change in the meantime.
  final TagFolder? tag;

  /// Where this entry has got to.
  final DownloadQueueState state;

  /// How many times it has been tried. Shown on a failed row so a wallpaper
  /// that keeps failing looks different from one that failed once.
  final int attempts;

  /// Why the last attempt failed, or null if it has not.
  ///
  /// Reuses [ImageStoreProblem] rather than restating it: that enum is already
  /// the domain's safe vocabulary for a storage failure — no URL, no path — and
  /// a parallel copy would be one more pair of lists to keep in agreement.
  final ImageStoreProblem? failure;

  /// When it was queued. Orders the queue, oldest first — a queue is a line.
  final DateTime queuedAt;

  /// What identifies this entry, on both halves of the key.
  WallpaperRef get ref => wallpaper.ref;

  @override
  bool operator ==(Object other) => other is QueuedDownload && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;

  /// Names the entry and its state, and nothing about where it would land —
  /// the same rule that keeps stored paths out of `DownloadRecord.toString`.
  @override
  String toString() => 'QueuedDownload($ref, ${state.name})';
}
