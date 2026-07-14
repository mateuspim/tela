import 'package:meta/meta.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/resolution.dart';

/// How a listing constrains the size of the wallpapers it asks for.
///
/// **Sealed, and that is the point.** Wallhaven has two size params and they
/// conflict: send `atleast` and `resolutions` together and it honours `atleast`
/// and *silently ignores* `resolutions` (checked against the real server,
/// 2026-07-14 — `atleast=1920x1080&resolutions=2560x1440` answers with the
/// at-least listing). A filter that can only ever be one of the three cannot
/// express the combination that loses.
///
/// ```dart
/// const AtLeastResolution(Resolution(1920, 1080)).toQueryParameters();
/// ```
@immutable
sealed class ResolutionFilter {
  const ResolutionFilter();

  /// The params this filter contributes to `/search`.
  Map<String, String> toQueryParameters();

  /// The stored form, e.g. `auto`, `atleast:1080x2400`, `exact:1920x1080`.
  String encode();

  /// Reads back what [encode] wrote, or null when it names nothing.
  ///
  /// Null rather than a throw: the caller is reading a snapshot tela did not
  /// write this run, and an unreadable one must cost the *filter* — falling
  /// back to [AutomaticResolution], which is where every listing already
  /// starts — rather than the screen it sits on.
  static ResolutionFilter? tryParse(String stored) {
    if (stored == _autoTag) return const AutomaticResolution();
    final int separator = stored.indexOf(':');
    if (separator < 0) return null;

    final String tag = stored.substring(0, separator);
    final String value = stored.substring(separator + 1);
    return switch (tag) {
      _atLeastTag => _tryParseAtLeast(value),
      _exactTag => _tryParseExact(value),
      _ => null,
    };
  }

  static ResolutionFilter? _tryParseAtLeast(String value) {
    final Resolution? minimum = Resolution.tryParse(value);
    if (minimum == null) return null;
    return AtLeastResolution(minimum);
  }

  /// All-or-nothing, unlike the ratios' per-entry fail-soft. A resolution list
  /// is *exact*: dropping one unreadable entry silently narrows the filter to
  /// the survivors, which is a different listing rather than a smaller one.
  static ResolutionFilter? _tryParseExact(String value) {
    final List<Resolution?> parsed = value
        .split(',')
        .map(Resolution.tryParse)
        .toList(growable: false);
    if (parsed.isEmpty || parsed.contains(null)) return null;
    return ExactResolutions(parsed.cast<Resolution>());
  }

  static const String _autoTag = 'auto';
  static const String _atLeastTag = 'atleast';
  static const String _exactTag = 'exact';
}

/// Fit the screen tela is actually running on. The default.
///
/// It carries no resolution of its own — the domain has no idea how big the
/// screen is — so it emits nothing, and is turned into an [AtLeastResolution]
/// by `SearchQuery.forScreen` at the point where a widget can answer the
/// question. Before that it means "ask me later", which is why an unresolved
/// one sending no size param is correct rather than a silent hole: an
/// unfiltered listing is what tela showed before it knew the screen either.
final class AutomaticResolution extends ResolutionFilter {
  /// Creates the default filter.
  const AutomaticResolution();

  @override
  Map<String, String> toQueryParameters() => const <String, String>{};

  @override
  String encode() => ResolutionFilter._autoTag;

  @override
  bool operator ==(Object other) => other is AutomaticResolution;

  @override
  int get hashCode => ResolutionFilter._autoTag.hashCode;
}

/// Nothing smaller than [minimum] — Wallhaven's `atleast`.
///
/// What a wallpaper app wants nearly always: an image *larger* than the screen
/// still looks sharp once it is set, and a smaller one never does.
final class AtLeastResolution extends ResolutionFilter {
  /// Creates the filter.
  const AtLeastResolution(this.minimum);

  /// The smallest acceptable size.
  final Resolution minimum;

  @override
  Map<String, String> toQueryParameters() => <String, String>{
    'atleast': minimum.toApiValue(),
  };

  @override
  String encode() => '${ResolutionFilter._atLeastTag}:${minimum.toApiValue()}';

  @override
  bool operator ==(Object other) =>
      other is AtLeastResolution && other.minimum == minimum;

  @override
  int get hashCode => minimum.hashCode;
}

/// These sizes and no others — Wallhaven's `resolutions`, a union.
///
/// Exact, and unforgiving with it: a size nobody has uploaded returns an
/// *empty* grid rather than a near miss (`resolutions=720x1280` has zero
/// wallpapers on the real server, where `atleast=720x1280` has plenty). That is
/// why [offerableResolutions] offers only sizes Wallhaven actually has, and why
/// [AutomaticResolution] stays the default.
final class ExactResolutions extends ResolutionFilter {
  /// Creates the filter. At least one size, or it asks for nothing at all.
  ///
  /// Deliberately not `const`: the emptiness check is what keeps a
  /// `resolutions=` with nothing after it off the wire, and Dart cannot
  /// evaluate a collection in a const assert. The guard is worth more than the
  /// keyword — an empty exact filter is not a wider listing, it is a malformed
  /// request.
  ExactResolutions(this.sizes)
    : assert(
        sizes.isNotEmpty,
        'exact resolutions must name at least one size',
      );

  /// The sizes to accept, as a union.
  final List<Resolution> sizes;

  @override
  Map<String, String> toQueryParameters() => <String, String>{
    'resolutions': sizes.map((Resolution size) => size.toApiValue()).join(','),
  };

  @override
  String encode() {
    final String joined = sizes
        .map((Resolution size) => size.toApiValue())
        .join(',');
    return '${ResolutionFilter._exactTag}:$joined';
  }

  @override
  bool operator ==(Object other) {
    return other is ExactResolutions &&
        other.sizes.length == sizes.length &&
        other.sizes.toSet().containsAll(sizes);
  }

  @override
  int get hashCode => Object.hashAllUnordered(sizes);
}

/// The sizes the filter sheet offers, grouped by the ratio they share.
///
/// [screen]'s own bucket leads, and the screen itself is in it: "exactly the
/// size I am holding" is the one exact resolution a phone user is likely to
/// want, and it is not in any standard ladder.
///
/// Every offered size is one Wallhaven **actually has**, which is the same rule
/// as `offerablePurities` and `offerableRatios` — an option the server cannot
/// answer is not offered. It bites harder here than anywhere else:
/// `resolutions` is an exact match, so an unpopular size is not a narrower
/// listing, it is an empty one. `720x1280` is the case that made the point
/// (zero wallpapers on the real server, 2026-07-14), and it is why the portrait
/// ladder starts at 1080p.
///
/// ```dart
/// offerableResolutions(const Resolution(1080, 2400)).first.ratio; // 9x20
/// ```
List<ResolutionBucket> offerableResolutions(Resolution screen) {
  final ExactRatio shape = ExactRatio.ofScreen(screen);
  final List<ResolutionBucket> buckets = <ResolutionBucket>[
    for (final ResolutionBucket bucket in _standardBuckets)
      if (bucket.ratio == shape)
        ResolutionBucket(ratio: shape, sizes: _withScreen(bucket.sizes, screen))
      else
        bucket,
  ];

  // A phone whose shape has no standard ladder still deserves its own size.
  if (!buckets.any((ResolutionBucket bucket) => bucket.ratio == shape)) {
    buckets.insert(
      0,
      ResolutionBucket(ratio: shape, sizes: <Resolution>[screen]),
    );
    return buckets;
  }

  buckets.sort((ResolutionBucket a, ResolutionBucket b) {
    if (a.ratio == shape) return -1;
    if (b.ratio == shape) return 1;
    return 0;
  });
  return buckets;
}

/// [sizes] with the device's own [screen] among them, largest last.
List<Resolution> _withScreen(List<Resolution> sizes, Resolution screen) {
  if (sizes.contains(screen)) return sizes;
  return <Resolution>[...sizes, screen]..sort(
    (Resolution a, Resolution b) => (a.width * a.height).compareTo(
      b.width * b.height,
    ),
  );
}

/// One ratio's worth of offered sizes.
@immutable
class ResolutionBucket {
  /// Creates the bucket.
  const ResolutionBucket({required this.ratio, required this.sizes});

  /// The shape every size in [sizes] shares — the heading of the group.
  final ExactRatio ratio;

  /// The sizes, smallest first.
  final List<Resolution> sizes;

  @override
  bool operator ==(Object other) {
    return other is ResolutionBucket &&
        other.ratio == ratio &&
        other.sizes.length == sizes.length &&
        other.sizes.toSet().containsAll(sizes);
  }

  @override
  int get hashCode => Object.hash(ratio, Object.hashAllUnordered(sizes));
}

/// wallhaven.cc's own resolution ladders, minus the sizes it has no wallpapers
/// at. Checked against the real server on 2026-07-14; the totals in the
/// comments are why each ladder starts where it does.
const List<ResolutionBucket> _standardBuckets = <ResolutionBucket>[
  // Portrait. Scarce on a desktop wallpaper site — 1080x1920 has ~1.7k and
  // 1440x2560 ~290 — and 720x1280 has *none*, which is why it is not here.
  ResolutionBucket(
    ratio: ExactRatio(9, 16),
    sizes: <Resolution>[Resolution(1080, 1920), Resolution(1440, 2560)],
  ),
  ResolutionBucket(
    ratio: ExactRatio(16, 9),
    sizes: <Resolution>[
      Resolution(1600, 900),
      Resolution(1920, 1080),
      Resolution(2560, 1440),
      Resolution(3840, 2160),
    ],
  ),
  ResolutionBucket(
    ratio: ExactRatio(16, 10),
    sizes: <Resolution>[
      Resolution(1280, 800),
      Resolution(1920, 1200),
      Resolution(2560, 1600),
      Resolution(3840, 2400),
    ],
  ),
  // Ultrawide, and the one bucket whose heading is a *family* rather than an
  // exact shape. Neither of these sizes actually reduces to 21x9 (2560x1080 is
  // 64x27, 3440x1440 is 43x18), and Wallhaven groups them under `21x9` anyway —
  // `ratios=21x9` answers with 2.33, 2.37 *and* 2.39 (real server, 2026-07-14).
  // So the label is Wallhaven's own, and it is the one that finds them.
  ResolutionBucket(
    ratio: ExactRatio(21, 9),
    sizes: <Resolution>[Resolution(2560, 1080), Resolution(3440, 1440)],
  ),
];
