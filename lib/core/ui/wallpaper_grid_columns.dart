import 'package:flutter/material.dart';

/// Logical width each wallpaper tile aims at, in dips.
const double _targetTileWidth = 220;

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
/// ```dart
/// Container(foregroundDecoration: wallpaperTileEdge(scheme), child: thumb);
/// ```
BoxDecoration wallpaperTileEdge(ColorScheme scheme) => BoxDecoration(
  borderRadius: BorderRadius.circular(wallpaperTileRadius),
  border: Border.all(color: scheme.outlineVariant.withValues(alpha: .22)),
);

/// Columns for a masonry wallpaper grid, sized by available width.
///
/// Two columns is right on a phone and absurd on a tablet, where it yields two
/// ~1200px-wide tiles. Shared by every wallpaper grid so browse and favorites
/// cannot drift into different shapes on the same device.
///
/// ```dart
/// MasonryGridView.count(crossAxisCount: wallpaperGridColumns(context));
/// ```
int wallpaperGridColumns(BuildContext context) {
  final double width = MediaQuery.sizeOf(context).width;
  return (width / _targetTileWidth).round().clamp(2, 6);
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
