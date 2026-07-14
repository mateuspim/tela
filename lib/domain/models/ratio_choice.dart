import 'package:meta/meta.dart';
import 'package:tela/domain/models/resolution.dart';

/// One entry of Wallhaven's `ratios` param: an exact shape, or one of its two
/// orientation keywords.
///
/// Ratios are a **union** in the API — `ratios=16x9,9x16` returns both — unlike
/// `colors`, which matches one bucket at a time. So a listing carries a *list*
/// of these and the filter sheet offers chips rather than a radio.
///
/// Named for the ratios it sets, not `Orientation`: Flutter already has an
/// `Orientation` enum and every file with the filter sheet in it imports
/// Material.
///
/// ```dart
/// const ExactRatio(9, 16).toApiValue(); // '9x16'
/// ShapeRatio.portrait.toApiValue();     // 'portrait'
/// ```
@immutable
sealed class RatioChoice {
  const RatioChoice();

  /// The literal this choice contributes to the `ratios` param.
  String toApiValue();

  /// Reads back one `ratios` literal, or null when it names nothing.
  ///
  /// Null rather than a throw, because every caller is reading a value tela did
  /// not write this run — a stored snapshot, chiefly — and an unreadable one
  /// must cost that ratio and not the snapshot it sits in. It matters that it
  /// is caught here: Wallhaven **silently ignores** a `ratios` value it cannot
  /// read and answers with an *unfiltered* grid (confirmed against the real
  /// server, 2026-07-14: `ratios=bogus` returns the same mixed listing as no
  /// filter at all). Passing a corrupt literal straight through would therefore
  /// read on screen as a filter that quietly does nothing.
  static RatioChoice? tryParse(String raw) {
    return ShapeRatio.tryParse(raw) ?? ExactRatio.tryParse(raw);
  }

  /// Encodes [choices] as the `ratios` param expects, or null for "any shape".
  ///
  /// Null rather than an empty string: an empty `ratios=` is not how you ask
  /// Wallhaven for every shape — you omit the param.
  static String? encode(List<RatioChoice> choices) {
    if (choices.isEmpty) return null;
    return choices.map((RatioChoice choice) => choice.toApiValue()).join(',');
  }

  /// Reads back a whole encoded list, dropping any entry that names nothing.
  ///
  /// Fail-soft per entry, like `WallpaperColor.readAll`: one corrupt ratio
  /// costs that ratio, not the four beside it.
  static List<RatioChoice> readAll(String encoded) {
    if (encoded.isEmpty) return const <RatioChoice>[];
    return encoded
        .split(',')
        .map(RatioChoice.tryParse)
        .nonNulls
        .toList(growable: false);
  }
}

/// Wallhaven's `portrait` and `landscape` keywords: *every* ratio of that
/// shape.
///
/// Broader than any exact ratio, and not a synonym for one — `portrait` returns
/// 0.56, 0.7, 0.78 and everything else taller than it is wide (confirmed
/// against the real server), where `9x16` returns 0.56 and nothing else.
///
/// An enum rather than a class, so that a `switch` over [RatioChoice] is
/// exhaustive over *both* keywords: a third one Wallhaven adds later becomes a
/// compile error at every label, rather than a chip with a wire word on it.
enum ShapeRatio implements RatioChoice {
  /// Anything taller than it is wide.
  portrait('portrait'),

  /// Anything wider than it is tall.
  landscape('landscape');

  const ShapeRatio(this.keyword);

  /// The literal Wallhaven expects.
  final String keyword;

  /// The keyword [raw] names, or null when it names neither.
  static ShapeRatio? tryParse(String raw) {
    return values.where((ShapeRatio shape) => shape.keyword == raw).firstOrNull;
  }

  @override
  String toApiValue() => keyword;
}

/// One exact aspect ratio, e.g. `16x9`.
///
/// **Wallhaven accepts an arbitrary `WxH` here, not a fixed vocabulary** — this
/// was settled against the real server (2026-07-14): `ratios=9x20` comes back
/// with 24 wallpapers all at ratio 0.45, and `9x19` all at 0.47. That is what
/// makes [ExactRatio.ofScreen] worth offering: a modern phone reduces to a
/// shape like 9x20, which appears in no wallpaper site's dropdown, and
/// Wallhaven honours it anyway.
final class ExactRatio extends RatioChoice {
  /// Creates a ratio from an already-reduced pair, e.g. `ExactRatio(16, 9)`.
  const ExactRatio(this.width, this.height)
    : assert(width > 0, 'width must be > 0'),
      assert(height > 0, 'height must be > 0');

  /// The reduced ratio of [screen] — 1080x2400 becomes `9x20`.
  ///
  /// The recommendation the filter sheet leads with: the shape of the device
  /// the user is actually holding is the shape they most likely want a
  /// wallpaper in, and it is a shape no fixed dropdown offers.
  ///
  /// **A reduced ratio takes the standard spelling of its own shape when there
  /// is one**, and that is not cosmetics. A 2560x1600 tablet reduces to `8x5`,
  /// which Wallhaven honours exactly as it honours `16x10` (both answer with
  /// ratio 1.6 — checked against the real server, 2026-07-14). But then
  /// [offerableRatios] would offer `8x5` *and* `16x10` — two chips that are the
  /// same filter, spelled differently, where selecting one leaves the other
  /// looking unselected. Naming the shape the way Wallhaven names it is what
  /// lets the device's chip *be* the standard chip when it is one.
  factory ExactRatio.ofScreen(Resolution screen) {
    final int divisor = _gcd(screen.width, screen.height);
    final ExactRatio reduced = ExactRatio(
      screen.width ~/ divisor,
      screen.height ~/ divisor,
    );
    return _standardRatios.firstWhere(
      reduced.isSameShapeAs,
      orElse: () => reduced,
    );
  }

  /// The `<width>x<height>` form, or null when [raw] is not one.
  static ExactRatio? tryParse(String raw) {
    final List<String> parts = raw.split('x');
    if (parts.length != 2) return null;
    final int? width = int.tryParse(parts[0]);
    final int? height = int.tryParse(parts[1]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return ExactRatio(width, height);
  }

  /// Left half of the ratio.
  final int width;

  /// Right half of the ratio.
  final int height;

  /// Whether this is a taller-than-wide shape — what a phone wants.
  bool get isPortrait => height > width;

  /// Whether [other] describes the same proportions, however it is spelled.
  ///
  /// `8x5` and `16x10` are one shape and one filter; only [==] tells them
  /// apart, and it must, because they are different strings on the wire.
  bool isSameShapeAs(ExactRatio other) =>
      width * other.height == other.width * height;

  @override
  String toApiValue() => '${width}x$height';

  @override
  bool operator ==(Object other) =>
      other is ExactRatio && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => toApiValue();

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
}

/// The ratios the filter sheet offers, most useful on a phone first.
///
/// [screen] leads the list as the recommendation, and is *not* repeated further
/// down when it happens to be one of the standard shapes — a tablet at
/// 2560x1600 reduces to `16x10`, which is already here.
///
/// The standard shapes are the ones wallhaven.cc's own filter bar offers, all
/// of which were confirmed to filter for real against the API (2026-07-14).
/// Every one is *offerable* precisely because Wallhaven answers it; an option
/// it could not honour would not be offered, which is the same rule as
/// `offerablePurities` and `offerableSortings`.
///
/// ```dart
/// offerableRatios(const Resolution(1080, 2400)).first; // ExactRatio(9, 20)
/// ```
List<RatioChoice> offerableRatios(Resolution screen) {
  final ExactRatio device = ExactRatio.ofScreen(screen);
  return <RatioChoice>[
    device,
    ...ShapeRatio.values,
    ..._standardRatios.where((ExactRatio ratio) => ratio != device),
  ];
}

/// wallhaven.cc's own ratio vocabulary: portrait, wide, ultrawide, and boxy.
const List<ExactRatio> _standardRatios = <ExactRatio>[
  ExactRatio(9, 16),
  ExactRatio(10, 16),
  ExactRatio(9, 18),
  ExactRatio(16, 9),
  ExactRatio(16, 10),
  ExactRatio(21, 9),
  ExactRatio(32, 9),
  ExactRatio(48, 9),
  ExactRatio(1, 1),
  ExactRatio(3, 2),
  ExactRatio(4, 3),
  ExactRatio(5, 4),
];
