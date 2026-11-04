/// Which way a local library lists its images by the time they were saved.
///
/// The private library only ever listed newest first, with no way to walk it
/// from the start (owner, 2026-11-04: *"we dont have a way to sort them by most
/// recent first or oldest"*). [newestFirst] is that shipped order, so it is
/// what an unset preference reads back as.
///
/// ```dart
/// final List<DateTime> sorted = LibraryOrder.oldestFirst.sorted(
///   saved,
///   savedAt: (DateTime at) => at,
///   tieBreak: (DateTime at) => at.toIso8601String(),
/// );
/// ```
enum LibraryOrder {
  /// The most recently saved first — the order the library always had.
  newestFirst,

  /// The earliest saved first.
  oldestFirst;

  /// Parses a stored constant name, or null when absent or unknown, so an
  /// unreadable row costs the preference and not the screen.
  static LibraryOrder? tryFromName(String? raw) {
    if (raw == null) return null;
    return LibraryOrder.values
        .where((LibraryOrder order) => order.name == raw)
        .firstOrNull;
  }

  /// A copy of [items] in this order by [savedAt].
  ///
  /// Ties break on [tieBreak], ascending either way, so a batch saved in the
  /// same instant keeps one stable order across rebuilds — `List.sort` makes
  /// no stability promise, and a grid reshuffling on its own reads as a bug.
  List<T> sorted<T>(
    Iterable<T> items, {
    required DateTime Function(T item) savedAt,
    required String Function(T item) tieBreak,
  }) {
    final int direction = this == LibraryOrder.newestFirst ? -1 : 1;
    return items.toList()..sort((T a, T b) {
      final int bySaved = savedAt(a).compareTo(savedAt(b)) * direction;
      return bySaved != 0 ? bySaved : tieBreak(a).compareTo(tieBreak(b));
    });
  }
}
