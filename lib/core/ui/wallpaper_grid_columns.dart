import 'package:flutter/material.dart';
import 'package:tela/domain/models/tile_density.dart';

/// Logical width a wallpaper tile aims at, in dips, at each density.
///
/// The dips live here rather than on [TileDensity] so the domain stays a
/// statement of the user's choice and this file stays the only place the wall's
/// measurements are written down. Medium is the 220 every build drew before the
/// setting existed, so the default density is not a change.
double _targetTileWidth(TileDensity density) => switch (density) {
  TileDensity.small => 150,
  TileDensity.medium => 220,
  TileDensity.large => 320,
};

/// The most tiles a row may hold at each density.
///
/// Density has to move this too, or the clamp eats the knob: on the tablet a
/// small target width rounds past six and gets clamped back to exactly what
/// medium already drew, while a large one still permits a six-up row.
int _maxPerRow(TileDensity density) => switch (density) {
  TileDensity.small => 9,
  TileDensity.medium => 6,
  TileDensity.large => 4,
};

/// The 12dp masonry rhythm every wallpaper shelf packs to.
///
/// One constant so Browse, Favorites, History, and the private library cannot
/// drift into different gutters on the same device.
const double wallpaperGridSpacing = 12;

/// The 16dp corner every wallpaper tile is clipped to, across all four shelves.
const double wallpaperTileRadius = 16;

/// A hairline drawn *over* a thumbnail's edge so a near-white or near-black
/// wallpaper does not melt into the surface it sits on.
///
/// The gutter alone cannot separate a pale image from a pale background; this
/// gives every tile a faint containing edge in the same `outlineVariant`
/// language the theme's cards already use, kept low enough not to box the wall
/// in. Applied as a `foregroundDecoration` so it rides on top of the image,
/// inside the tile's clip, on every shelf — Browse, Favorites, History, and the
/// private library — through one definition they cannot drift apart from.
///
/// Detail's letterbox-filling preview borrows the same edge against its own
/// blurred backdrop, where the problem is identical and the source of the pale
/// background is the wallpaper itself. It passes [radius] 0: that frame is an
/// uncropped rectangle, not a tile, so a rounded hairline would trace a corner
/// the image does not have.
///
/// ```dart
/// Container(foregroundDecoration: wallpaperTileEdge(scheme), child: thumb);
/// ```
BoxDecoration wallpaperTileEdge(
  ColorScheme scheme, {
  double radius = wallpaperTileRadius,
}) => BoxDecoration(
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: scheme.outlineVariant.withValues(alpha: .22)),
);

/// The height a justified shelf aims its rows at, for a shelf [availableWidth]
/// dips wide, drawn at [density].
///
/// Derived from the same target width the row cap uses, so a justified row
/// holds roughly as many landscape wallpapers as the old masonry had columns,
/// and the wall keeps its density on both a phone and the tablet. The 1.5
/// divisor is the compromise shape between a 16:9 landscape and a square: rows
/// of wide wallpapers come out a little shorter than the target, rows carrying
/// portraits a little taller, which is exactly the give that lets mixed
/// orientations share a row without anyone being cropped.
///
/// The column count here is deliberately **fractional**, unlike the cap's.
/// Rounding it would quantise the density knob away at the widths where two
/// densities round to the same count — a 500dip shelf (an unfolded foldable, a
/// small tablet in portrait) rounds to two columns at both medium and large, so
/// a rounded divisor would hand them the identical height and "Large" would
/// visibly do nothing there.
///
/// ```dart
/// justifiedRows(targetRowHeight: wallpaperRowHeight(width, density), ...);
/// ```
double wallpaperRowHeight(double availableWidth, TileDensity density) {
  final double columns = availableWidth / _targetTileWidth(density);
  final double columnWidth =
      (availableWidth - wallpaperGridSpacing * (columns - 1)) / columns;
  return columnWidth / 1.5;
}

/// The most wallpapers one justified row may hold on a shelf [availableWidth]
/// dips wide, drawn at [density].
///
/// The same count the masonry used as columns, reused as a cap so a row of
/// portrait wallpapers stays as large as a column of them used to be. Without
/// it a wide shelf packs phone-shaped thumbs a dozen to the row before the row
/// is short enough to close, and none of them is big enough to judge.
///
/// ```dart
/// justifiedRows(maxPerRow: wallpaperRowTileCap(width, density), ...);
/// ```
int wallpaperRowTileCap(double availableWidth, TileDensity density) {
  return (availableWidth / _targetTileWidth(density)).round().clamp(
    2,
    _maxPerRow(density),
  );
}

/// Edge padding for a wallpaper shelf: the 12dp rhythm, plus whatever system
/// safe area is not already consumed by the surrounding chrome.
///
/// The top is left to the shelf's app bar. The sides and bottom add the live
/// [MediaQueryData.padding] so a landscape notch or a full-screen gesture bar
/// never clips the last row — and add nothing (the inset reads back as zero)
/// when a bottom navigation bar or rail has already reserved that space.
///
/// ```dart
/// MasonryGridView.count(padding: wallpaperGridPadding(context));
/// ```
EdgeInsets wallpaperGridPadding(BuildContext context) {
  final EdgeInsets safeArea = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(
    wallpaperGridSpacing + safeArea.left,
    wallpaperGridSpacing,
    wallpaperGridSpacing + safeArea.right,
    wallpaperGridSpacing + safeArea.bottom,
  );
}
