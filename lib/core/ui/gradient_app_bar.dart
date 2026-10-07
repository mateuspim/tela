import 'package:flutter/material.dart';
import 'package:tela/core/ui/floating_capsule.dart';

/// An [AppBar] on an opaque, faintly brand-warmed vertical wash that settles
/// into the plain surface, so the chrome reads as a crafted band instead of a
/// flat rectangle — with nothing showing behind it.
///
/// No bottom rule: the wash already ends on the body's own colour, and a
/// hairline there made the seam to the wall read sharp (owner, 2026-10-06).
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
    super.leading,
    super.leadingWidth,
    super.automaticallyImplyLeading,
  }) : super(
         // The wash lives in flexibleSpace; the bar itself paints nothing so it
         // does not sit an opaque colour in front of the gradient.
         backgroundColor: Colors.transparent,
         surfaceTintColor: Colors.transparent,
         scrolledUnderElevation: 0,
         elevation: 0,
         flexibleSpace: const _GradientBand(),
       );

  /// The bar for a screen pushed over a tab — a listing, collections,
  /// download history, the private library — whose back button floats in a
  /// [FloatingCapsule] like the actions beside it, instead of standing bare
  /// on the band (device survey, 2026-10-05).
  ///
  /// A separate constructor rather than a capsule on every bar: a tab's root
  /// screen has no back button, and a reserved leading slot would shift its
  /// title.
  ///
  /// ```dart
  /// Scaffold(appBar: GradientAppBar.pushed(title: Text(name)));
  /// ```
  GradientAppBar.pushed({
    Key? key,
    Widget? title,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
    double? toolbarHeight,
  }) : this(
         key: key,
         title: title,
         actions: actions,
         bottom: bottom,
         toolbarHeight: toolbarHeight,
         automaticallyImplyLeading: false,
         // Inset 16 from the edge, the band's own side gutter.
         leadingWidth: 16 + kMinInteractiveDimension + 8,
         leading: const Padding(
           padding: EdgeInsetsDirectional.only(start: 16),
           child: Align(
             alignment: AlignmentDirectional.centerStart,
             child: FloatingCapsule(child: BackButton()),
           ),
         ),
         titleSpacing: 8,
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
