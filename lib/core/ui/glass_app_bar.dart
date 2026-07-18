import 'dart:ui';

import 'package:flutter/material.dart';

/// An [AppBar] whose surface is frosted glass: the wall scrolling beneath it
/// blurs through a translucent, faintly accent-washed pane instead of hiding
/// behind an opaque band.
///
/// The signature of tela's expressive chrome. It only reads as glass when the
/// body actually passes underneath, so pair it with
/// `Scaffold(extendBodyBehindAppBar: true)` — an opaque body just blurs a flat
/// colour and wastes the effect. That flag also does the layout work: Scaffold
/// folds the bar's height into the body's `MediaQuery.padding.top`, which the
/// wallpaper grids already honour through `wallpaperGridPadding`, so the first
/// row clears the bar while the rest scrolls under it. A grid that reads its
/// padding from a context *above* the Scaffold body (a captured `build` arg)
/// misses that inset and slides under the bar — wrap such a body in a
/// `Builder`.
///
/// ```dart
/// Scaffold(
///   extendBodyBehindAppBar: true,
///   appBar: GlassAppBar(title: const BrowseSearchField()),
///   body: grid,
/// );
/// ```
class GlassAppBar extends AppBar {
  /// Creates a frosted app bar. [title], [actions] and [bottom] behave exactly
  /// as on a plain [AppBar]; the frost is supplied for you.
  GlassAppBar({
    super.key,
    super.title,
    super.actions,
    super.bottom,
    super.toolbarHeight,
    super.titleSpacing,
  }) : super(
         // The frost lives in flexibleSpace, so the bar itself paints nothing:
         // a coloured background would sit in front of the blur and hide it.
         backgroundColor: Colors.transparent,
         surfaceTintColor: Colors.transparent,
         scrolledUnderElevation: 0,
         elevation: 0,
         flexibleSpace: const _FrostedPane(),
       );
}

/// The blurred, translucent pane painted behind a [GlassAppBar]'s contents.
class _FrostedPane extends StatelessWidget {
  const _FrostedPane();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipRect(
      // Without the clip the blur samples — and smears — the whole screen, not
      // just the strip behind the bar.
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                // A hint of brand up top, a legible near-surface pane below the
                // text. These three are the on-device tuning knobs.
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: .10),
                  scheme.surface.withValues(alpha: _topAlpha),
                ),
                scheme.surface.withValues(alpha: _bottomAlpha),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const double _blurSigma = 20;
  static const double _topAlpha = .72;
  static const double _bottomAlpha = .86;
}
