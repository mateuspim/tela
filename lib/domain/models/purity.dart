/// How explicit a wallpaper is, as Wallhaven classifies it.
///
/// Wallhaven speaks two dialects for purity and they are *not* the same shape:
/// a wallpaper's own JSON carries a name (`"sfw"`), while the `/search` query
/// param carries a 3-bit mask (`"110"` = sfw+sketchy). Hence [fromApiName] and
/// [PurityFilter.toApiBits] rather than one `toString`.
///
/// ```dart
/// Purity.fromApiName('sketchy'); // Purity.sketchy
/// ```
enum Purity {
  /// Safe for work. The default, and the only purity that needs no API key.
  sfw,

  /// Suggestive but not explicit. Needs no key, but is off by default.
  sketchy,

  /// Explicit. Requires a valid API key, and triggers every rule in the NSFW
  /// section of CLAUDE.md — never MediaStore-indexed, never logged.
  nsfw;

  /// Parses the `purity` field of a wallpaper JSON object.
  ///
  /// ```dart
  /// Purity.fromApiName('nsfw'); // Purity.nsfw
  /// ```
  static Purity fromApiName(String raw) {
    final Purity? purity = tryFromApiName(raw);
    if (purity == null) {
      throw ArgumentError('purity must be sfw|sketchy|nsfw, got "$raw"');
    }
    return purity;
  }

  /// Parses a purity name, answering null instead of throwing.
  ///
  /// For payloads where one unreadable name must cost that name and nothing
  /// else — the account's purity list, where a bucket Wallhaven adds and tela
  /// does not know yet should not fail the whole sync.
  static Purity? tryFromApiName(String raw) {
    return switch (raw) {
      'sfw' => Purity.sfw,
      'sketchy' => Purity.sketchy,
      'nsfw' => Purity.nsfw,
      _ => null,
    };
  }

  /// Whether a Wallhaven API key is required to see wallpapers of this purity.
  bool get requiresApiKey => this == Purity.nsfw;
}

/// The set of purities a search asks for, encoded as Wallhaven's 3-bit mask.
///
/// Bit order is fixed by the API: `sfw sketchy nsfw`, so `"100"` is sfw-only
/// and `"111"` is everything.
///
/// ```dart
/// const PurityFilter({Purity.sfw, Purity.sketchy}).toApiBits(); // '110'
/// ```
extension type const PurityFilter(Set<Purity> purities) {
  /// The default: safe content only, which needs no API key.
  static const PurityFilter sfwOnly = PurityFilter({Purity.sfw});

  /// Encodes to the 3-bit `purity` query param.
  String toApiBits() {
    final String bits = Purity.values
        .map((Purity p) => purities.contains(p) ? '1' : '0')
        .join();
    if (bits == '000') {
      throw ArgumentError(
        'purity filter must select at least one of sfw|sketchy|nsfw, got none',
      );
    }
    return bits;
  }

  /// True when this filter cannot be served without an API key.
  bool get requiresApiKey => purities.any((Purity p) => p.requiresApiKey);
}
