import 'package:flutter/widgets.dart';

/// Logical width each wallpaper tile aims at, in dips.
const double _targetTileWidth = 220;

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
