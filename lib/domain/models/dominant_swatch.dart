import 'package:tela/domain/models/ambient_seed.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

/// The colour a photograph is mostly made of, or null when it is made of grey.
///
/// What a source that reports no palette of its own is answered with, so a
/// Konachan wallpaper can tint its screen the way a Wallhaven one does. Takes
/// 24-bit RGB [pixels] — the adapter's job is decoding an image down to those,
/// and this file's job is the choice, which is the part worth testing without
/// one.
///
/// Deliberately **not** an average: averaging a photograph yields the muddy
/// brown-grey halfway between everything in it, which is the one colour the
/// picture does not contain. This buckets instead, and answers with the
/// most-populated bucket — the colour the most pixels actually are.
///
/// ```dart
/// dominantSwatch(<int>[0x0066cc, 0x0066cc, 0x333333])?.hex; // '#0066cc'
/// ```
WallpaperColor? dominantSwatch(Iterable<int> pixels) {
  final Map<int, _Bucket> buckets = <int, _Bucket>{};
  for (final int pixel in pixels) {
    final int red = (pixel >> 16) & 0xFF;
    final int green = (pixel >> 8) & 0xFF;
    final int blue = pixel & 0xFF;
    if (!_hasColour(red, green, blue)) continue;
    buckets
        .putIfAbsent(_keyOf(red, green, blue), _Bucket.new)
        .add(
          red,
          green,
          blue,
        );
  }
  return _winner(buckets);
}

/// How far apart a pixel's channels must be before it counts as a colour.
///
/// Near-greys are the majority of most photographs — shadow, cloud, concrete,
/// skin in low light — and counting them lets a picture with one vivid subject
/// be described by its background. This is the same judgement `canTint` makes
/// about a *reported* colour, applied a pixel at a time and with a margin,
/// because a photograph's greys are never exactly equal the way a palette
/// entry's are.
const int _minimumChroma = 24;

/// Bits of precision kept per channel when bucketing.
///
/// Four, so 4096 buckets. Finer splits one flat wall across a dozen of them and
/// lets a small vivid area win on a technicality; coarser merges colours a
/// viewer would call different.
const int _bucketBits = 4;

bool _hasColour(int red, int green, int blue) {
  final int high = red > green
      ? (red > blue ? red : blue)
      : (green > blue ? green : blue);
  final int low = red < green
      ? (red < blue ? red : blue)
      : (green < blue ? green : blue);
  return high - low >= _minimumChroma;
}

int _keyOf(int red, int green, int blue) {
  const int shift = 8 - _bucketBits;
  return ((red >> shift) << (_bucketBits * 2)) |
      ((green >> shift) << _bucketBits) |
      (blue >> shift);
}

/// The fullest bucket's own average, or null when nothing had colour in it.
///
/// The average is taken *within* the winning bucket rather than across the
/// image, so it is a real colour from a real region — the bucket's centre would
/// be a colour no pixel is, off by up to half a bucket in every channel.
WallpaperColor? _winner(Map<int, _Bucket> buckets) {
  _Bucket? best;
  for (final _Bucket bucket in buckets.values) {
    if (best == null || bucket.count > best.count) best = bucket;
  }
  if (best == null) return null;
  final WallpaperColor colour = best.average();
  // A bucket can average out flatter than the pixels that filled it, so the
  // shared rule is applied once more at the end rather than trusted from the
  // per-pixel filter.
  return canTint(colour) ? colour : null;
}

/// Running totals for one colour bucket.
class _Bucket {
  int count = 0;
  int _red = 0;
  int _green = 0;
  int _blue = 0;

  void add(int red, int green, int blue) {
    count++;
    _red += red;
    _green += green;
    _blue += blue;
  }

  WallpaperColor average() {
    final String hex = <int>[_red, _green, _blue]
        .map((int total) => (total ~/ count).toRadixString(16).padLeft(2, '0'))
        .join();
    return WallpaperColor('#$hex');
  }
}
