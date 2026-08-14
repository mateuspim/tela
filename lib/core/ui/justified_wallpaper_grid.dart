import 'package:flutter/material.dart';
import 'package:tela/core/ui/justified_rows.dart';
import 'package:tela/core/ui/tile_density_scope.dart';
import 'package:tela/core/ui/tile_entrance.dart';
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
class JustifiedWallpaperGrid extends StatefulWidget {
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

  /// The gap between one tile's arrival and the next along a row.
  static const Duration entranceStagger = Duration(milliseconds: 45);

  /// How many tiles a cascade may stagger before they all arrive together.
  ///
  /// A nine-up row at *Small* would otherwise keep its last tile waiting most
  /// of half a second, which stops reading as one row assembling and starts
  /// reading as a slow shelf.
  static const int maxStaggered = 6;

  @override
  State<JustifiedWallpaperGrid> createState() => _JustifiedWallpaperGridState();
}

class _JustifiedWallpaperGridState extends State<JustifiedWallpaperGrid> {
  /// Wallpapers this shelf has already drawn once.
  ///
  /// Lives here because the State is the only thing that outlives the rows: a
  /// `ListView` recycles them, so a tile scrolled off and back would otherwise
  /// arrive as if it were new and the wall would flicker under a scroll. Kept
  /// by list index, which is stable for an append-only paged shelf — the same
  /// property `justifiedRows` already relies on to be safe to append to.
  final Set<int> _seen = <int>{};

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
        return _rows(context, width, constraints.maxHeight, padding);
      },
    );
  }

  Widget _rows(
    BuildContext context,
    double width,
    double height,
    EdgeInsets padding,
  ) {
    final TileDensity density = TileDensityScope.of(context);
    final List<JustifiedRow> rows = justifiedRows(
      aspectRatios: List<double>.generate(
        widget.itemCount,
        widget.aspectRatioOf,
      ),
      availableWidth: width,
      targetRowHeight: wallpaperRowHeight(width, density),
      spacing: wallpaperGridSpacing,
      maxPerRow: wallpaperRowTileCap(width, density),
      // Only a shelf that never closed a row uses this, and it needs a real
      // viewport to measure against. An unbounded height means nobody has told
      // this shelf how tall it is, so there is nothing to take two thirds of —
      // fall through to the packer's own ceiling rather than invent one.
      soleRowMaxHeight: height.isFinite ? soleWallpaperRowHeight(height) : null,
    );
    final Widget? trailing = widget.footer;
    return ListView.builder(
      controller: widget.controller,
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
    // Recorded while building, which is deliberate: this is a cache of what has
    // been drawn, not state anything rebuilds on, and the answer is needed by
    // the very widget being built. Reduce-motion collapses it to "seen", so a
    // device that wants no motion also pays nothing to track it.
    final bool fresh =
        !MediaQuery.disableAnimationsOf(context) && _seen.add(tile.index);
    final Widget built = SizedBox(
      width: tile.width,
      height: tile.height,
      child: TileEntrance(
        animate: fresh,
        delay:
            JustifiedWallpaperGrid.entranceStagger *
            (position.clamp(0, JustifiedWallpaperGrid.maxStaggered)),
        child: widget.itemBuilder(
          context,
          tile.index,
          tile.width,
          tile.height,
        ),
      ),
    );
    if (position == 0) return built;
    return Padding(
      padding: const EdgeInsets.only(left: wallpaperGridSpacing),
      child: built,
    );
  }
}
