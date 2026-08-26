import 'package:meta/meta.dart';

/// What phase a background offload is in.
enum OffloadPhase {
  /// Reading each file across to the card. The long part, and the only one
  /// that can report a position.
  copying,

  /// Copying is done and the originals cannot be removed yet, because the
  /// gallery's delete confirmation is the OS's own and only a screen can raise
  /// it. See `AppVisibility`.
  waitingForScreen,

  /// Removing the originals. One call, no per-file progress — and on Android
  /// 30+ this is where the system prompt appears.
  removing,

  /// Over. [OffloadRun.moved] against [OffloadRun.total] is the whole result.
  done,
}

/// One offload, as it runs and after it finishes.
///
/// Lives above every screen so the move survives leaving the one that started
/// it, which is the entire point of running it in the background.
@immutable
class OffloadRun {
  /// Creates a run in [phase], having copied [copied] of [total].
  const OffloadRun({
    required this.phase,
    required this.total,
    this.copied = 0,
    this.moved = 0,
    this.bytes = 0,
    this.stopping = false,
    this.failed = false,
    this.includesPrivateLibrary = false,
  });

  /// Where the run has got to.
  final OffloadPhase phase;

  /// How many files it was asked to move.
  final int total;

  /// Whether the private library was one of the piles ticked for this run.
  ///
  /// Carried from the selection at `OffloadRunController.start` rather than
  /// read back off the moves themselves: it answers what the *user asked
  /// for*, which is what decides whether `OffloadRunController._reroute` also
  /// switches explicit downloads — and so what the finished screen should say
  /// happened to them.
  final bool includesPrivateLibrary;

  /// How many have been copied so far — attempts, not successes, so one
  /// unreadable file does not look like a stall.
  final int copied;

  /// How many completed the whole trip. Only meaningful once [isDone].
  final int moved;

  /// What the selection was measured at, for the report at the end.
  final int bytes;

  /// Whether a stop has been asked for and not yet taken effect.
  ///
  /// A stop ends the *copying*; whatever is already copied still has its
  /// original removed, so the run goes on to [OffloadPhase.removing] rather
  /// than vanishing. Surfacing the request separately is what lets the button
  /// disable itself instead of looking ignored.
  final bool stopping;

  /// Whether the move failed outright rather than moving a subset.
  final bool failed;

  /// Whether the run has finished, however it went.
  bool get isDone => phase == OffloadPhase.done;

  /// Whether files are still being read across — the only phase with a
  /// position worth drawing as a bar.
  bool get isCopying => phase == OffloadPhase.copying;

  /// Whether everything asked for made the trip.
  bool get isComplete => isDone && !failed && moved == total;

  /// A copy of this run in [phase], carrying the counters forward.
  OffloadRun at(
    OffloadPhase phase, {
    int? copied,
    int? moved,
    bool? stopping,
    bool? failed,
  }) {
    return OffloadRun(
      phase: phase,
      total: total,
      copied: copied ?? this.copied,
      moved: moved ?? this.moved,
      bytes: bytes,
      stopping: stopping ?? this.stopping,
      failed: failed ?? this.failed,
      includesPrivateLibrary: includesPrivateLibrary,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OffloadRun &&
      other.phase == phase &&
      other.total == total &&
      other.copied == copied &&
      other.moved == moved &&
      other.stopping == stopping &&
      other.failed == failed;

  @override
  int get hashCode =>
      Object.hash(phase, total, copied, moved, stopping, failed);

  @override
  String toString() =>
      'OffloadRun(${phase.name}, $copied/$total copied, $moved moved)';
}
