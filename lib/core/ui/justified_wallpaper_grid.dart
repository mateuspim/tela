import 'package:flutter/material.dart';
import 'package:tela/core/ui/justified_rows.dart';
import 'package:tela/core/ui/tile_density_scope.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/domain/models/tile_density.dart';

/// Builds the tile at [index], already sized to [width] by [height].
///
/// The size is passed in rather than left to the child because the row, not the
/// tile, decides how tall everything in it is — a tile that sized itself would
/// break the row's shared height.
typedef JustifiedTileBuilder =
    Widget Function(
      BuildContext context,
      int index,
      double width,
      double height,
    );

/// A wallpaper shelf laid out in full-width rows of a shared height.
///
/// Replaces the masonry every shelf used to use. Masonry drops each tile into
/// the shortest column, so the tile to the right of another is often the one
/// *before* it in the listing, and a viewer paging by index looks like it skips
/// around. Rows here are real, so reading order is list order and the viewer
/// needs no compensation — see `justifiedRows` for the packing and why it is
/// safe to append to.
///
/// ```dart
/// JustifiedWallpaperGrid(
///   itemCount: wallpapers.length,
///   aspectRatioOf: (int i) => wallpapers[i].resolution.aspectRatio,
///   itemBuilder: (_, int i, double w, double h) => WallpaperTile(...),
/// )
/// ```
class JustifiedWallpaperGrid extends StatelessWidget {
  /// Creates a justified shelf of [itemCount] wallpapers.
  const JustifiedWallpaperGrid({
    required this.itemCount,
    required this.aspectRatioOf,
    required this.itemBuilder,
    this.controller,
    this.footer,
    super.key,
  });

  /// How many wallpapers the shelf holds.
  final int itemCount;

  /// The true aspect ratio of the wallpaper at an index, width over height.
  final double Function(int index) aspectRatioOf;

  /// Builds one tile at the size its row assigned it.
  final JustifiedTileBuilder itemBuilder;

  /// Optional scroll controller, so a paged shelf can watch for the end.
  final ScrollController? controller;

  /// Optional widget pinned after the last row — a paged shelf's next-page
  /// spinner or its retry, which must scroll with the wall rather than float
  /// over it.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = wallpaperGridPadding(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width =
            constraints.maxWidth - padding.left - padding.right;
        // A zero-width pass happens during some route transitions; packing
        // against it would throw rather than simply draw nothing yet.
        if (width <= 0) return const SizedBox.shrink();
        return _rows(context, width, padding);
      },
    );
  }

  Widget _rows(BuildContext context, double width, EdgeInsets padding) {
    final TileDensity density = TileDensityScope.of(context);
    final List<JustifiedRow> rows = justifiedRows(
      aspectRatios: List<double>.generate(itemCount, aspectRatioOf),
      availableWidth: width,
      targetRowHeight: wallpaperRowHeight(width, density),
      spacing: wallpaperGridSpacing,
      maxPerRow: wallpaperRowTileCap(width, density),
    );
    final Widget? trailing = footer;
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: rows.length + (trailing == null ? 0 : 1),
      itemBuilder: (BuildContext context, int index) {
        if (index == rows.length) return trailing;
        return _row(context, rows[index]);
      },
    );
  }

  Widget _row(BuildContext context, JustifiedRow row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: wallpaperGridSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int position = 0; position < row.tiles.length; position++)
            _tile(context, row.tiles[position], position),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, JustifiedTile tile, int position) {
    final Widget built = SizedBox(
      width: tile.width,
      height: tile.height,
      child: itemBuilder(context, tile.index, tile.width, tile.height),
    );
    if (position == 0) return built;
    return Padding(
      padding: const EdgeInsets.only(left: wallpaperGridSpacing),
      child: built,
    );
  }
}
