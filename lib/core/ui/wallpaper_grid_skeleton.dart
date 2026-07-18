import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/justified_rows.dart';
import 'package:tela/core/ui/tile_density_scope.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/domain/models/tile_density.dart';

/// The placeholder wall a shelf shows while its first wallpapers are still
/// loading: tiles under a slow shimmer, packed by the very same `justifiedRows`
/// the real wall uses, so the preview cannot drift from what arrives.
///
/// A centred spinner told the user nothing about what was coming and left most
/// of the screen empty; this previews the layout instead, so the wall does not
/// jump when the images arrive. Shared by every shelf — Browse's first page,
/// Favorites, History, the private library — so "loading" reads the same
/// everywhere, at the same columns and inset as the grid it stands in for.
///
/// It lays its tiles out **without a scroll view of its own** and clips the
/// overflow, so it sizes correctly both as a bounded screen body and inside the
/// content-sized `SliverFillRemaining` that hosts a pager's first-page
/// indicator (a nested [ScrollView] there cannot report an intrinsic height and
/// throws). Honours reduced motion: the sweep is dropped and the tiles rest
/// static, so nobody who asked the system to still animation gets a shimmer.
///
/// ```dart
/// favorites.when(loading: WallpaperGridSkeleton.new, data: _grid, ...);
/// ```
class WallpaperGridSkeleton extends StatefulWidget {
  /// Creates the loading skeleton.
  const WallpaperGridSkeleton({super.key});

  @override
  State<WallpaperGridSkeleton> createState() => _WallpaperGridSkeletonState();
}

class _WallpaperGridSkeletonState extends State<WallpaperGridSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.disableAnimationsOf(context);
    _drive(motionless: still);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget wall = Padding(
      padding: wallpaperGridPadding(context),
      child: _rows(scheme),
    );
    return Semantics(
      label: AppLocalizations.of(context).gridLoading,
      container: true,
      child: ExcludeSemantics(
        child: ClipRect(
          child: still ? wall : _shimmer(wall, scheme),
        ),
      ),
    );
  }

  /// Runs the sweep only when motion is allowed, so a reduced-motion frame does
  /// not leave a controller repeating forever behind a static wall.
  void _drive({required bool motionless}) {
    if (motionless) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      unawaited(_sweep.repeat());
    }
  }

  /// The tiles in justified rows — packed by the real layout function, not an
  /// imitation of it, so the skeleton cannot promise a shape the wall then
  /// fails to deliver. Let to overrun the viewport, since the [ClipRect] above
  /// hides whatever falls past the bottom edge.
  Widget _rows(ColorScheme scheme) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        if (width <= 0) return const SizedBox.shrink();
        final TileDensity density = TileDensityScope.of(context);
        final List<JustifiedRow> rows = justifiedRows(
          aspectRatios: _skeletonRatios,
          availableWidth: width,
          targetRowHeight: wallpaperRowHeight(width, density),
          spacing: wallpaperGridSpacing,
          maxPerRow: wallpaperRowTileCap(width, density),
        );
        return OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final JustifiedRow row in rows) _row(scheme, row),
            ],
          ),
        );
      },
    );
  }

  Widget _row(ColorScheme scheme, JustifiedRow row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: wallpaperGridSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < row.tiles.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: wallpaperGridSpacing),
            _tile(scheme, row.tiles[i]),
          ],
        ],
      ),
    );
  }

  Widget _tile(ColorScheme scheme, JustifiedTile tile) {
    return WallpaperSkeletonTile(
      scheme: scheme,
      width: tile.width,
      height: tile.height,
    );
  }

  /// Enough shapes to overrun any viewport: the sample ratios, repeated.
  static final List<double> _skeletonRatios = <double>[
    for (int repeat = 0; repeat < 4; repeat++) ..._tileRatios,
  ];

  /// Paints a light band that slides across the tiles, only where they are
  /// opaque (`srcATop`), so the gutters between them stay dark.
  Widget _shimmer(Widget masonry, ColorScheme scheme) {
    return AnimatedBuilder(
      animation: _sweep,
      child: masonry,
      builder: (BuildContext context, Widget? child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (Rect bounds) => _band(scheme).createShader(bounds),
        child: child,
      ),
    );
  }

  /// The three-stop highlight, its window slid from off-left to off-right as
  /// [_sweep] runs — a moving glint over the resting surface tone.
  LinearGradient _band(ColorScheme scheme) {
    final double centre = _sweep.value * 3 - 1.5;
    return LinearGradient(
      begin: Alignment(centre - .6, 0),
      end: Alignment(centre + .6, 0),
      colors: <Color>[
        scheme.surfaceContainerHighest,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
      ],
    );
  }

  /// Aspect ratios cycled through the placeholder tiles, portrait-leaning like
  /// most phone wallpapers, so the masonry looks packed rather than gridded.
  static const List<double> _tileRatios = <double>[
    0.68,
    1,
    0.75,
    1.5,
    0.63,
    1.2,
    0.7,
    0.9,
    0.66,
    1.33,
    0.72,
    0.8,
  ];
}

/// One resting placeholder tile: the tile's surface tone, its corner, and the
/// same hairline edge the real tiles carry.
///
/// A named widget rather than an inline box so a test can find the
/// placeholders themselves — and read back the size its row assigned — instead
/// of guessing which layout box happens to wrap them.
class WallpaperSkeletonTile extends StatelessWidget {
  /// Creates a placeholder of [width] by [height].
  const WallpaperSkeletonTile({
    required this.scheme,
    required this.width,
    required this.height,
    super.key,
  });

  /// Colours the resting surface and its hairline edge.
  final ColorScheme scheme;

  /// Width the packed row assigned this placeholder.
  final double width;

  /// The row's shared height.
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(wallpaperTileRadius),
        ),
        child: DecoratedBox(decoration: wallpaperTileEdge(scheme)),
      ),
    );
  }
}
