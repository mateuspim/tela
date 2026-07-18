import 'package:flutter/widgets.dart';

/// Logical width each wallpaper tile aims at, in dips.
const double _targetTileWidth = 220;

/// The 12dp masonry rhythm every wallpaper shelf packs to.
///
/// One constant so Browse, Favorites, History, and the private library cannot
/// drift into different gutters on the same device.
const double wallpaperGridSpacing = 12;

/// The 16dp corner every wallpaper tile is clipped to, across all four shelves.
const double wallpaperTileRadius = 16;

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
/// Every edge adds the live [MediaQueryData.padding] so a landscape notch or a
/// full-screen gesture bar never clips a row — and adds nothing (the inset
/// reads back as zero) when surrounding chrome has already reserved that space.
///
/// The top matters under a `GlassAppBar`: with `extendBodyBehindAppBar` the
/// grid scrolls beneath the frosted bar, and a `GlassBody` injects the bar's
/// height into the top inset so the first row starts clear of it. Under an
/// opaque app bar the Scaffold has already consumed that inset, so the top
/// reads back as the bare rhythm — the behaviour every non-glass shelf had.
///
/// ```dart
/// MasonryGridView.count(padding: wallpaperGridPadding(context));
/// ```
EdgeInsets wallpaperGridPadding(BuildContext context) {
  final EdgeInsets safeArea = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(
    wallpaperGridSpacing + safeArea.left,
    wallpaperGridSpacing + safeArea.top,
    wallpaperGridSpacing + safeArea.right,
    wallpaperGridSpacing + safeArea.bottom,
  );
}
