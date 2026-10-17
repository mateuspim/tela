import 'package:tela/domain/models/stored_bits.dart';

/// How explicit a wallpaper is.
///
/// Nearly isomorphic to a booru's safe/questionable/explicit, which is lucky
/// and load-bearing: CLAUDE.md's NSFW rules key on [Purity.nsfw], so every
/// source's adapter maps its own vocabulary onto these three — failing closed,
/// an unrecognised rating becoming [Purity.nsfw] (PLAN §17.4).
///
/// Sources spell the names differently, so the *encoding* of a purity — and of
/// a whole [PurityFilter] — belongs to each adapter, not here.
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

  /// Whether an API key is required to see wallpapers of this purity.
  ///
  /// True of Wallhaven; a source that serves explicit content anonymously —
  /// Konachan does, verified live — reads this through its own capabilities
  /// rather than being refused locally.
  bool get requiresApiKey => this == Purity.nsfw;

  /// The most explicit purity in [purities] — the one whose warning the
  /// download chooser shows over a mixed batch — or [Purity.sfw] for an empty
  /// set.
  ///
  /// ```dart
  /// Purity.strongestOf({Purity.sfw, Purity.nsfw}); // Purity.nsfw
  /// ```
  static Purity strongestOf(Set<Purity> purities) {
    return purities.fold(
      Purity.sfw,
      (Purity worst, Purity p) => p.index > worst.index ? p : worst,
    );
  }
}

/// The set of purities a search asks for.
///
/// ```dart
/// const PurityFilter({Purity.sfw, Purity.sketchy}).requiresApiKey; // false
/// ```
extension type const PurityFilter(Set<Purity> purities) {
  /// The default: safe content only, which needs no API key.
  static const PurityFilter sfwOnly = PurityFilter({Purity.sfw});

  /// True when this filter cannot be served without an API key.
  bool get requiresApiKey => purities.any((Purity p) => p.requiresApiKey);

  /// This filter with [Purity.nsfw] taken out, or [sfwOnly] when nothing else
  /// was in it — the fail-safe direction when there is no key to unlock it.
  PurityFilter withoutNsfw() {
    final Set<Purity> rest = <Purity>{...purities}..remove(Purity.nsfw);
    return rest.isEmpty ? sfwOnly : PurityFilter(rest);
  }

  /// Encodes to the 3-bit mask tela stores a saved filter as, in the fixed
  /// order `sfw sketchy nsfw` — see `CategoryFilter.encodeStored`.
  String encodeStored() => encodeStoredBits(Purity.values, purities);

  /// Reads back a mask [encodeStored] wrote, or null if [bits] is not one.
  static PurityFilter? tryParseStored(String bits) {
    final Set<Purity>? selected = decodeStoredBits(bits, Purity.values);
    return selected == null ? null : PurityFilter(selected);
  }
}
