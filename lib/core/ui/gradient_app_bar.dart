import 'package:flutter/material.dart';

/// An [AppBar] on an opaque, faintly brand-warmed vertical wash with a hairline
/// bottom edge, so the chrome reads as a crafted band instead of a flat
/// rectangle — with nothing showing behind it.
///
/// Deliberately **opaque**. A see-through bar over a wall of wallpaper
/// thumbnails reads as broken — the frosted-glass attempt proved it on device —
/// so the wash stays solid and the grid stops cleanly beneath the bar. Unlike a
/// frosted bar it needs no `extendBodyBehindAppBar`: the Scaffold reserves the
/// bar's height as always, and grid padding is untouched.
///
/// ```dart
/// Scaffold(
///   appBar: GradientAppBar(title: const BrowseSearchField()),
///   body: grid,
/// );
/// ```
class GradientAppBar extends AppBar {
  /// Creates the gradient app bar. [title], [actions] and [bottom] behave
  /// exactly as on a plain [AppBar]; the wash is supplied for you.
  GradientAppBar({
    super.key,
    super.title,
    super.actions,
    super.bottom,
    super.toolbarHeight,
    super.titleSpacing,
  }) : super(
         // The wash lives in flexibleSpace; the bar itself paints nothing so it
         // does not sit an opaque colour in front of the gradient.
         backgroundColor: Colors.transparent,
         surfaceTintColor: Colors.transparent,
         scrolledUnderElevation: 0,
         elevation: 0,
         flexibleSpace: const _GradientBand(),
       );
}

/// The opaque wash painted behind a [GradientAppBar]'s contents.
class _GradientBand extends StatelessWidget {
  const _GradientBand();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            // A raised, brand-warmed top settling to the plain surface the grid
            // sits on. Both stops are opaque — the alpha blend sits the accent
            // *over* an opaque container — so no wall shows through.
            //
            // surfaceContainer, not Highest: the floating capsules ride this
            // band in surfaceBright, and a Highest top was within a few levels
            // of them — the search capsule all but vanished (SM-X730,
            // 2026-10-05, the first time the band ever painted).
            Color.alphaBlend(
              scheme.primary.withValues(alpha: _accentWash),
              scheme.surfaceContainer,
            ),
            scheme.surface,
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
      ),
      // The child is what gives the band a size. AppBar stacks flexibleSpace
      // with StackFit.passthrough under loose constraints, where a childless
      // DecoratedBox takes the minimum: zero height. Without this the wash
      // never painted at all (SM-X730, 2026-10-05).
      child: const SizedBox.expand(),
    );
  }

  /// How much brand tint warms the top edge — the tuning knob.
  static const double _accentWash = .10;
}
