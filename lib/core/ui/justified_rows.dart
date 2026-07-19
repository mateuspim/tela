/// Packs wallpapers of differing shapes into rows that share one height and
/// span the full width, without cropping any of them.
///
/// This is the layout Flickr and Google Photos use, and tela uses it for one
/// specific reason: it has genuine *rows*. A masonry grid does not — it drops
/// each tile into whichever column is shortest, so the tile visually to the
/// right of another can easily be the one *before* it in the listing. That
/// makes a viewer which pages by list index look like it skips around, because
/// the eye reads in rows the layout never actually had. Here, reading order and
/// list order are the same thing by construction, so the viewer, the Hero tags,
/// and the session need no compensation at all.
///
/// The trade is that a portrait sharing a row with wide tiles comes out
/// narrow. The target row height is the dial for that: taller rows hold
/// fewer, larger tiles.
library;

/// One wallpaper's box within a packed row.
class JustifiedTile {
  /// Places the wallpaper at [index] in a box of [width] by [height].
  const JustifiedTile({
    required this.index,
    required this.width,
    required this.height,
  });

  /// Position in the source list the row was packed from.
  final int index;

  /// Laid-out width, already scaled to the row's shared height.
  final double width;

  /// The row's shared height, repeated here so a tile is self-describing.
  final double height;
}

/// A run of wallpapers laid out side by side at one shared height.
class JustifiedRow {
  /// Creates a row of [tiles], every one [height] tall.
  const JustifiedRow({required this.tiles, required this.height});

  /// The wallpapers in this row, in reading order.
  final List<JustifiedTile> tiles;

  /// The height every tile in the row was scaled to.
  final double height;
}

/// Packs [aspectRatios] into full-width rows of a shared height.
///
/// Fills a row until its height falls to [targetRowHeight] or it reaches
/// [maxPerRow] tiles, then closes it — so rows land near that height without
/// ever being forced to it, and every tile keeps its true aspect ratio. The
/// final row reaches for the full width too, capped at the height of the row
/// above it — see [_trailingHeight] for why an uncapped fill is unusable.
///
/// [soleRowMaxHeight] is the ceiling for a shelf so short that **no row ever
/// closed** — a library holding one or two wallpapers. Without it such a shelf
/// is capped at [targetRowHeight], which is the height the layout aims *rows of
/// a full wall* at, so the only thing on screen is drawn as small as a tile
/// among hundreds: one favorite came out 93dip tall on a 753dip tablet
/// viewport, adrift above a screen and a half of black (device, 2026-07-19).
/// Defaults to [targetRowHeight], which is exactly the old behaviour.
///
/// [maxPerRow] is what keeps portrait wallpapers usable. Height alone is the
/// wrong stop for them: phone-shaped tiles are narrow, so a wide shelf can fit
/// a dozen before the row is short enough to close, leaving a strip of
/// thumbnails too small to judge. Capping the count instead lets a row of
/// portraits simply be tall — which is exactly how they looked in the columns
/// this layout replaced.
///
/// Row `n` never depends on anything after it, which is what makes this safe
/// under pagination: appending a page can only re-pack the trailing partial
/// row, never disturb the rows already on screen.
///
/// ```dart
/// final List<JustifiedRow> rows = justifiedRows(
///   aspectRatios: <double>[16 / 9, 9 / 16, 1],
///   availableWidth: 1200,
///   targetRowHeight: 240,
///   spacing: 12,
/// );
/// ```
List<JustifiedRow> justifiedRows({
  required List<double> aspectRatios,
  required double availableWidth,
  required double targetRowHeight,
  required double spacing,
  required int maxPerRow,
  double? soleRowMaxHeight,
}) {
  _checkPositive(availableWidth, 'availableWidth');
  _checkPositive(targetRowHeight, 'targetRowHeight');
  if (maxPerRow < 1) {
    throw ArgumentError.value(maxPerRow, 'maxPerRow', 'must fit >= 1 tile');
  }
  if (spacing < 0 || !spacing.isFinite) {
    throw ArgumentError.value(spacing, 'spacing', 'must be a finite gap >= 0');
  }
  final List<JustifiedRow> rows = <JustifiedRow>[];
  final List<int> pending = <int>[];
  double pendingRatio = 0;
  for (int index = 0; index < aspectRatios.length; index++) {
    pending.add(index);
    pendingRatio += _checkRatio(aspectRatios[index]);
    final double height = _rowHeight(
      totalRatio: pendingRatio,
      count: pending.length,
      availableWidth: availableWidth,
      spacing: spacing,
    );
    if (height > targetRowHeight && pending.length < maxPerRow) continue;
    rows.add(_row(pending, aspectRatios, height));
    pending.clear();
    pendingRatio = 0;
  }
  if (pending.isNotEmpty) {
    rows.add(
      _row(
        pending,
        aspectRatios,
        _trailingHeight(
          pending: pending,
          pendingRatio: pendingRatio,
          rows: rows,
          availableWidth: availableWidth,
          targetRowHeight: targetRowHeight,
          soleRowMaxHeight: soleRowMaxHeight,
          spacing: spacing,
        ),
      ),
    );
  }
  return rows;
}

/// How tall to draw the leftover row: as close to filling the width as it can
/// get without towering over the wall.
///
/// Filling the width and keeping the true aspect ratio are the same knob, so a
/// lone portrait stretched across a tablet would stand several screens tall.
/// The row above is the natural ceiling — matching it keeps the wall's rhythm,
/// and a leftover wide enough to fill at less than that height simply fills.
double _trailingHeight({
  required List<int> pending,
  required double pendingRatio,
  required List<JustifiedRow> rows,
  required double availableWidth,
  required double targetRowHeight,
  required double? soleRowMaxHeight,
  required double spacing,
}) {
  final double filling = _rowHeight(
    totalRatio: pendingRatio,
    count: pending.length,
    availableWidth: availableWidth,
    spacing: spacing,
  );
  // A shelf too short to have closed a row has no rhythm to match yet, so
  // [targetRowHeight] — a measurement about a *full* wall — is the wrong
  // ceiling for it: it shrinks the only content on screen to the size of a tile
  // among hundreds. [soleRowMaxHeight] is the caller's answer for that shelf.
  final double ceiling = rows.isEmpty
      ? (soleRowMaxHeight ?? targetRowHeight)
      : _larger(rows.last.height, targetRowHeight);
  return filling < ceiling ? filling : ceiling;
}

double _larger(double a, double b) => a > b ? a : b;

/// The height at which [count] tiles of [totalRatio] fill the width exactly.
double _rowHeight({
  required double totalRatio,
  required int count,
  required double availableWidth,
  required double spacing,
}) {
  final double gaps = spacing * (count - 1);
  return (availableWidth - gaps) / totalRatio;
}

JustifiedRow _row(List<int> indices, List<double> ratios, double height) {
  return JustifiedRow(
    height: height,
    tiles: <JustifiedTile>[
      for (final int index in indices)
        JustifiedTile(
          index: index,
          width: height * ratios[index],
          height: height,
        ),
    ],
  );
}

double _checkRatio(double aspectRatio) {
  if (!aspectRatio.isFinite || aspectRatio <= 0) {
    throw ArgumentError.value(
      aspectRatio,
      'aspectRatio',
      'must be a finite ratio greater than zero',
    );
  }
  return aspectRatio;
}

void _checkPositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'must be a finite length > 0');
  }
}
