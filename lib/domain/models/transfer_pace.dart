import 'package:meta/meta.dart';

/// How fast a long copy is going and how long it has left, from how much of it
/// is done after how long.
///
/// Unit-agnostic — bytes or files, whichever the caller has — and averaged
/// over the **whole run**, not the last few items. A card's per-file cost
/// swings threefold from one file to the next (creating the document is most
/// of it, and that varies), so a recent-window rate would make "time left"
/// jump about every second; the whole-run average settles and stays put, which
/// is what someone glancing at a 50-minute move needs from it.
///
/// ```dart
/// final TransferPace pace = TransferPace(
///   done: 12 << 30,
///   total: 65 << 30,
///   elapsed: const Duration(minutes: 10),
/// );
/// pace.remaining; // about 44 minutes
/// ```
@immutable
class TransferPace {
  /// Creates the pace of a copy that has done [done] of [total] in [elapsed].
  const TransferPace({
    required this.done,
    required this.total,
    required this.elapsed,
  });

  /// How long a run must go before it claims a speed at all.
  ///
  /// The first few files include folder creation on an empty card and a cold
  /// disk cache, so the rate they imply is the one number guaranteed to be
  /// wrong. Saying nothing for a few seconds beats a wild first guess.
  static const Duration settling = Duration(seconds: 5);

  /// How much is done, in the caller's unit.
  final int done;

  /// How much there is in all, in the same unit.
  final int total;

  /// How long the copy has been running.
  final Duration elapsed;

  /// The share done, from 0 to 1; 0 when there is nothing to measure against.
  double get fraction {
    if (total <= 0) return 0;
    return (done / total).clamp(0, 1).toDouble();
  }

  /// Units per second, or null until the run has [settling] and done something.
  double? get perSecond {
    if (elapsed < settling || done <= 0) return null;
    return done * Duration.microsecondsPerSecond / elapsed.inMicroseconds;
  }

  /// Time left at [perSecond], or null whenever that is.
  Duration? get remaining {
    final double? rate = perSecond;
    if (rate == null) return null;
    final int left = total - done < 0 ? 0 : total - done;
    return Duration(seconds: (left / rate).ceil());
  }
}
