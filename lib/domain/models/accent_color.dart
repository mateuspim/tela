/// A user-chosen brand accent, as a pure 24-bit RGB value.
///
/// Domain-pure on purpose: it holds the channels as an `int` and a `#rrggbb`
/// string, and has no `Color` to paint with — the theme layer turns it into
/// one. *Absence* of an accent (follow the device palette / Material You) is
/// modelled as a null [AccentColor] at the port boundary, never as a sentinel
/// value in here, so "the user picked nothing" and "the user picked black" stay
/// different facts.
///
/// ```dart
/// AccentColor.fromHex('#2C63E0').hex; // '#2c63e0'
/// AccentColor(0x2c63e0).rgb;          // 2909664
/// ```
extension type const AccentColor._(int rgb) {
  /// Wraps a 24-bit RGB value, rejecting anything with bits above `0xFFFFFF`.
  ///
  /// The channels only: an accent is opaque, and a value carrying alpha is a
  /// caller that forgot to strip it — which would paint a translucent brand
  /// colour, so it is refused rather than masked.
  factory AccentColor(int rgb) {
    if (rgb < 0 || rgb > 0xFFFFFF) {
      throw ArgumentError('accent must be 24-bit rgb 0..0xFFFFFF, got $rgb');
    }
    return AccentColor._(rgb);
  }

  /// Parses a `#rrggbb` colour, as the settings row and the picker both spell
  /// it. A leading `#` is optional so a stored `2c63e0` reads back the same.
  ///
  /// ```dart
  /// AccentColor.fromHex('2c63e0') == AccentColor.fromHex('#2C63E0'); // true
  /// ```
  factory AccentColor.fromHex(String raw) {
    final AccentColor? parsed = tryFromHex(raw);
    if (parsed == null) {
      throw ArgumentError('accent must be #rrggbb, got "$raw"');
    }
    return parsed;
  }

  /// Parses [raw], or answers null when it is absent or malformed.
  ///
  /// What the storage adapter reads with: a row it cannot make sense of costs
  /// the accent, not the app — the theme simply falls back to Material You,
  /// which is what an unset accent already means. A leading `#` is optional, so
  /// a stored `2c63e0` reads back the same.
  static AccentColor? tryFromHex(String? raw) {
    if (raw == null) return null;
    final String body = raw.startsWith('#') ? raw.substring(1) : raw;
    if (!_hexShape.hasMatch(body)) return null;
    return AccentColor._(int.parse(body, radix: 16));
  }

  /// The canonical `#rrggbb` form, lower-case and zero-padded — what the
  /// settings row stores and a `sqlite3` shell shows.
  String get hex => '#${rgb.toRadixString(16).padLeft(6, '0')}';

  static final RegExp _hexShape = RegExp(r'^[0-9a-fA-F]{6}$');
}
