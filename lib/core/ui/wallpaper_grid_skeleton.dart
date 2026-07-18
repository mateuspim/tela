import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';

/// The placeholder wall a shelf shows while its first wallpapers are still
/// loading: masonry-shaped tiles under a slow shimmer, in the exact grid rhythm
/// the real tiles will land in.
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
    final Widget masonry = Padding(
      padding: wallpaperGridPadding(context),
      child: _masonry(scheme),
    );
    return Semantics(
      label: AppLocalizations.of(context).gridLoading,
      container: true,
      child: ExcludeSemantics(
        child: ClipRect(
          child: still ? masonry : _shimmer(masonry, scheme),
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

  /// The tiles as balanced columns, packed round-robin so their differing
  /// heights read as masonry — and let to overrun the viewport, since the
  /// [ClipRect] above hides whatever falls past the bottom edge.
  Widget _masonry(ColorScheme scheme) {
    final int columns = wallpaperGridColumns(context);
    return OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int column = 0; column < columns; column++) ...<Widget>[
            if (column > 0) const SizedBox(width: wallpaperGridSpacing),
            Expanded(child: _column(scheme, column, columns)),
          ],
        ],
      ),
    );
  }

  /// One column: every [_tileRatios] entry whose index falls in this column.
  Widget _column(ColorScheme scheme, int start, int columns) {
    final List<Widget> tiles = <Widget>[];
    for (int i = start; i < _tileRatios.length; i += columns) {
      if (tiles.isNotEmpty) {
        tiles.add(const SizedBox(height: wallpaperGridSpacing));
      }
      tiles.add(_tile(scheme, _tileRatios[i]));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: tiles);
  }

  /// One resting placeholder tile: the tile's surface tone, its corner, and the
  /// same hairline edge the real tiles carry.
  Widget _tile(ColorScheme scheme, double ratio) {
    return AspectRatio(
      aspectRatio: ratio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(wallpaperTileRadius),
        ),
        child: DecoratedBox(decoration: wallpaperTileEdge(scheme)),
      ),
    );
  }

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
