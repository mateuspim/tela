import 'package:flutter/material.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';

/// Dissolves whatever scrolls up out of [child] into the surface, instead of
/// cutting it off at a hard line under the app bar.
///
/// The owner found the edge between the band and the wall too sharp
/// (2026-10-06), after the bottom strip had gone soft. The band already
/// settles to the plain surface, so a short surface-to-clear fade over the
/// body's top edge is all the seam needs.
///
/// [wallpaperGridSpacing] tall — the wall's own top padding — so a listing at
/// rest is untouched and only pictures on their way out fade.
///
/// ```dart
/// Scaffold(appBar: GradientAppBar(), body: BandFadeEdge(child: grid));
/// ```
class BandFadeEdge extends StatelessWidget {
  /// Fades the top edge of [child].
  const BandFadeEdge({required this.child, super.key});

  /// The scrolling body under the band.
  final Widget child;

  /// How tall the fade is.
  static const double height = wallpaperGridSpacing;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          // Over the wall, so it must never take a tap meant for a picture.
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[surface, surface.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
