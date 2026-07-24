import 'package:meta/meta.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// How many downloads in a row have landed in the same place.
///
/// The whole memory tela keeps about past downloads for this purpose: a tier
/// and a count, and **deliberately no wallpaper identity at all** — no id, no
/// path, no URL. It cannot say *what* was saved, only how many in a row went
/// the same way, which is what keeps it clear of the NSFW rules that the
/// download history has to obey by dropping rows.
///
/// ```dart
/// DownloadDestinationStreak.extending(null, StorageTier.appPrivate).length; // 1
/// ```
@immutable
class DownloadDestinationStreak {
  /// Creates a streak of [length] downloads that all landed in [tier].
  DownloadDestinationStreak({required this.tier, required this.length}) {
    if (length < 1) {
      throw ArgumentError('streak length must be 1 or more, got $length');
    }
  }

  /// The streak [current] becomes once a download lands in [tier].
  ///
  /// One longer when it matches [current], a fresh streak of 1 when it does
  /// not, and a fresh streak of 1 when there was no [current] at all. The
  /// arithmetic lives here rather than in each adapter so the Drift store and
  /// the test fake cannot count differently.
  ///
  /// ```dart
  /// DownloadDestinationStreak.extending(streak, StorageTier.appPrivate);
  /// ```
  factory DownloadDestinationStreak.extending(
    DownloadDestinationStreak? current,
    StorageTier tier,
  ) {
    if (current == null || current.tier != tier) {
      return DownloadDestinationStreak(tier: tier, length: 1);
    }
    return DownloadDestinationStreak(tier: tier, length: current.length + 1);
  }

  /// Where those downloads landed.
  final StorageTier tier;

  /// How many consecutive downloads landed there. Always 1 or more — a streak
  /// of zero is the *absence* of a streak, which is spelled `null`.
  final int length;

  /// Reads back what [encode] wrote; null for anything it did not write.
  ///
  /// Never throws. A row this cannot parse costs a *suggestion*, so the safe
  /// reading of an unreadable one is "no streak", not a guess.
  static DownloadDestinationStreak? tryParse(String? stored) {
    final List<String> parts = stored?.split(':') ?? <String>[];
    if (parts.length != 2) return null;
    final StorageTier? tier = StorageTier.values
        .where((StorageTier t) => t.name == parts.first)
        .firstOrNull;
    final int? length = int.tryParse(parts.last);
    if (tier == null || length == null || length < 1) return null;
    return DownloadDestinationStreak(tier: tier, length: length);
  }

  /// Encodes as `tier:count`, e.g. `appPrivate:3`.
  ///
  /// The tier's constant name rather than its index, so the row still reads
  /// correctly in a `sqlite3` shell and a reordered enum is not a silent
  /// rewrite of history — the same rule the storage-tier rows follow.
  String encode() => '${tier.name}:$length';

  @override
  bool operator ==(Object other) {
    return other is DownloadDestinationStreak &&
        other.tier == tier &&
        other.length == length;
  }

  @override
  int get hashCode => Object.hash(tier, length);

  @override
  String toString() => 'DownloadDestinationStreak(${tier.name} x$length)';
}
