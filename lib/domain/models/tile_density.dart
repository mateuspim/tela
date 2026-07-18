/// How large the wallpapers on a shelf are drawn.
///
/// Domain-pure on purpose: it is the user's *choice*, not a measurement — the
/// dips each step aims at live in `core/ui`, where the wall is packed, so a
/// layout tweak never becomes a stored-settings change. [medium] is what tela
/// has always drawn, so it is what an unset preference reads back as.
///
/// ```dart
/// TileDensity.tryFromName('large') ?? TileDensity.medium; // TileDensity.large
/// ```
enum TileDensity {
  /// More, smaller wallpapers to the row — a wall to scan.
  small,

  /// The shipped density, and the fallback for anything unreadable.
  medium,

  /// Fewer, larger wallpapers — closer to judging one before opening it.
  large;

  /// Parses a stored constant name, or answers null when it is absent or is not
  /// one of these.
  ///
  /// What the settings adapter reads with: a row it cannot make sense of costs
  /// the preference, not the app, and the caller falls back to [medium].
  static TileDensity? tryFromName(String? raw) {
    if (raw == null) return null;
    return TileDensity.values
        .where((TileDensity density) => density.name == raw)
        .firstOrNull;
  }
}
