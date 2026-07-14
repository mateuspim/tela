/// One colour from the fixed palette Wallhaven will filter a search by.
///
/// Same two-dialect problem as `Purity` and `Category`: a wallpaper's own JSON
/// carries `"#660000"`, while the `/search` query param wants a bare `660000`.
/// Hence [hex] and [toApiValue] rather than one `toString`.
///
/// Wallhaven quantizes every wallpaper's dominant colours down to [palette], so
/// the swatches offered as a filter are the same 29 values a wallpaper reports
/// — filtering by a colour you saw on a detail screen is guaranteed to be a
/// colour Wallhaven can actually search for.
///
/// ```dart
/// WallpaperColor('#0066cc').toApiValue(); // '0066cc'
/// ```
extension type const WallpaperColor._(String hex) {
  /// Parses a `#rrggbb` colour, as a wallpaper's JSON spells it.
  ///
  /// Validates the *shape* only, not membership of [palette]: Wallhaven's ToS
  /// reserves the right to change the API, and a 30th colour should widen
  /// the palette rather than crash a detail screen.
  factory WallpaperColor(String raw) {
    final String normalized = raw.toLowerCase();
    if (!_hexShape.hasMatch(normalized)) {
      throw ArgumentError('colour must be #rrggbb, got "$raw"');
    }
    return WallpaperColor._(normalized);
  }

  /// Reads every colour of [raw] that is one, and silently drops the rest.
  ///
  /// What the *display* path uses, where [WallpaperColor.new] is what the
  /// *filter* path uses. A wallpaper carries whatever colours Wallhaven gave
  /// it, and one unreadable swatch should cost that swatch — not the whole
  /// detail screen, which is what throwing on it would do.
  ///
  /// ```dart
  /// WallpaperColor.readAll(<String>['#660000', 'chartreuse']).length; // 1
  /// ```
  static List<WallpaperColor> readAll(Iterable<String> raw) {
    final List<WallpaperColor> read = <WallpaperColor>[];
    for (final String value in raw) {
      final String normalized = value.toLowerCase();
      if (_hexShape.hasMatch(normalized)) {
        read.add(WallpaperColor._(normalized));
      }
    }
    return read;
  }

  /// Encodes to the `colors` query param, which takes no leading `#`.
  String toApiValue() => hex.substring(1);

  /// The 24-bit RGB value, for a UI that wants to paint the swatch.
  ///
  /// Returns the channels only. Callers add their own alpha — the domain has no
  /// opinion about opacity, and no import of `Color` to express one with.
  int get rgb => int.parse(hex.substring(1), radix: 16);

  static final RegExp _hexShape = RegExp(r'^#[0-9a-f]{6}$');

  /// Every colour Wallhaven searches by, in the order its own UI shows them.
  ///
  /// A fixed list rather than a free hex field, because Wallhaven matches
  /// against these buckets: an arbitrary `#123456` returns nothing at all,
  /// which would read as a broken filter rather than an unsupported one.
  static const List<WallpaperColor> palette = <WallpaperColor>[
    WallpaperColor._('#660000'),
    WallpaperColor._('#990000'),
    WallpaperColor._('#cc0000'),
    WallpaperColor._('#cc3333'),
    WallpaperColor._('#ea4c88'),
    WallpaperColor._('#993399'),
    WallpaperColor._('#663399'),
    WallpaperColor._('#333399'),
    WallpaperColor._('#0066cc'),
    WallpaperColor._('#0099cc'),
    WallpaperColor._('#66cccc'),
    WallpaperColor._('#77cc33'),
    WallpaperColor._('#669900'),
    WallpaperColor._('#336600'),
    WallpaperColor._('#666600'),
    WallpaperColor._('#999900'),
    WallpaperColor._('#cccc33'),
    WallpaperColor._('#ffff00'),
    WallpaperColor._('#ffcc33'),
    WallpaperColor._('#ff9900'),
    WallpaperColor._('#ff6600'),
    WallpaperColor._('#cc6633'),
    WallpaperColor._('#996633'),
    WallpaperColor._('#663300'),
    WallpaperColor._('#000000'),
    WallpaperColor._('#999999'),
    WallpaperColor._('#cccccc'),
    WallpaperColor._('#ffffff'),
    WallpaperColor._('#424153'),
  ];
}
