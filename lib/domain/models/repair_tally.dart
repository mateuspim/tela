import 'package:meta/meta.dart';

/// How a broken-image repair went: [repaired] fetched again, [removed] deleted
/// because they could not be, and [failed] that could be neither.
///
/// ```dart
/// const RepairTally(repaired: 3, removed: 1, failed: 0).total; // 4
/// ```
@immutable
class RepairTally {
  /// Creates a tally.
  const RepairTally({
    required this.repaired,
    required this.removed,
    required this.failed,
  });

  /// Replaced with a freshly downloaded copy.
  final int repaired;

  /// Deleted, because no fresh copy could be had.
  final int removed;

  /// Still broken: neither re-downloaded nor deleted — a declined gallery
  /// prompt, or a delete the platform refused.
  final int failed;

  /// Every image the repair was asked about.
  int get total => repaired + removed + failed;

  @override
  bool operator ==(Object other) =>
      other is RepairTally &&
      other.repaired == repaired &&
      other.removed == removed &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(repaired, removed, failed);

  @override
  String toString() =>
      'RepairTally(repaired: $repaired, removed: $removed, failed: $failed)';
}
