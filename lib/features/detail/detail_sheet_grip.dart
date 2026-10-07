import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tela/features/detail/detail_editorial_body.dart';
import 'package:tela/features/detail/detail_top_scrim.dart';

/// The handle that says the sheet moves.
///
/// Drawn rather than taken from `BottomSheetThemeData.showDragHandle`, which
/// only applies to a `showModalBottomSheet` — this sheet is part of the page
/// and was never presented, so it inherits none of that theming.
///
/// Its colour travels with the surface it sits on. At rest there is no surface
/// at all — the handle is alone over the photograph, where `onSurfaceVariant`
/// is a mid grey that a pale sky swallows — so it is white there and settles
/// onto the scheme's own colour as the panel fades in.
///
/// White is not enough on its own, and the device proved it twice rather than
/// the argument. On a near-white wallpaper the plain white handle was
/// *invisible*; a shadow alone then measured **1.51:1** against a pure-white
/// one — a soft halo spreads its darkness over too many pixels to be an edge
/// (SM-X730, 2026-08-15). So it carries **both**, at exactly the strength the
/// missing surface owes it and none once the panel is solid: a hairline outline
/// that gives the bar a hard edge on white, and the shadow that lifts it off a
/// busy or mid-toned picture, which an outline alone cannot do.
///
/// Third time this project has paid for the same lesson — see
/// `wallpaperTileEdge` and [DetailTopScrim.opacity]: a control
/// over an arbitrary photograph cannot take its contrast on trust.
///
/// ```dart
/// DetailSheetGrip(alpha: surfaceAlpha, onTap: toggleSheet);
/// ```
class DetailSheetGrip extends StatelessWidget {
  /// Creates the handle over a surface whose solidity is [alpha].
  const DetailSheetGrip({required this.alpha, this.onTap, super.key});

  /// The grip's whole vertical footprint **at the peek** — Material's own
  /// minimum touch target, and therefore the closed sheet's whole height.
  ///
  /// It was [settledHeight], the bar plus its margins, which made the
  /// closed sheet 21dp tall: the entire hit area of the only control that
  /// opens the facts, at under half what a thumb is owed. The owner called it
  /// *"kinda hit or miss"* (2026-08-24), and both misses were loud — the apply
  /// button is glued immediately below — they share one surface — and since
  /// pass N the
  /// picture immediately above enters fullscreen on a tap. Nothing about the
  /// screen *looks* different for the change: the sheet is fully transparent
  /// at the peek (see [DetailEditorialBody.surfaceAlphaAt]), so what grew is
  /// an invisible target, and the cost is the bottom 48dp of the picture no
  /// longer taking a pinch.
  ///
  /// Flutter draws exactly this box for its own handle — `showDragHandle`
  /// constrains it to `kMinInteractiveDimension` — and this sheet only misses
  /// out because it is part of the page rather than presented, so none of that
  /// theming reaches it.
  static const double height = kMinInteractiveDimension;

  /// What the grip's band shrinks back to once the panel is solid — the
  /// footprint the bar and its margins had before any of this: 12 + 5 + 4.
  ///
  /// The reach is a closed-sheet problem — open, the handle is decoration and
  /// the facts are already under the thumb — so the target is spent where it
  /// is needed and given back where it is not. Without this an opened sheet
  /// would carry 48dp of blank above its first fact row, which is the kind of
  /// thing the peek's own history says gets noticed on a device.
  ///
  /// The bar is centred in whichever band it has, so growing the closed one
  /// lifts it **away** from the apply button rather than toward it — which is
  /// the half of "hit or miss" that was doing the damage.
  static const double settledHeight = 21;

  /// How solid the surface beneath the handle is, 0..1.
  final ValueListenable<double> alpha;

  /// Called when the band around the bar is tapped, to open or close the
  /// sheet. Null leaves the handle drag-only.
  final VoidCallback? onTap;

  /// The bar itself, before either of its defences.
  static const double _barWidth = 32;
  static const double _barHeight = 5;

  /// The outline's and the shadow's strength where the handle is alone over
  /// the wallpaper. Both scale to nothing as the panel fades in.
  static const double _outlineOpacity = 0.7;
  static const double _shadowOpacity = 0.45;

  /// The band's height at [solid] — see
  /// [height] for why it is not one number.
  ///
  /// ```dart
  /// DetailSheetGrip.bandHeightAt(0); // 48, the closed sheet's whole target
  /// ```
  static double bandHeightAt(double solid) {
    return lerpDouble(
      height,
      settledHeight,
      solid.clamp(0.0, 1.0),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final Color settled = Theme.of(context).colorScheme.onSurfaceVariant;
    // Opaque, so the whole band takes the tap and not just the 32x5 bar drawn
    // in the middle of it. It claims no drag, so the sheet underneath still
    // scrolls out from under a finger that meant to pull rather than tap.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ValueListenableBuilder<double>(
        valueListenable: alpha,
        builder: (BuildContext context, double solid, Widget? child) =>
            SizedBox(
              height: bandHeightAt(solid),
              child: Center(child: _bar(solid, settled)),
            ),
      ),
    );
  }

  Widget _bar(double solid, Color settled) {
    return Container(
      width: _barWidth,
      height: _barHeight,
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, settled, solid),
        borderRadius: BorderRadius.circular(_barHeight / 2),
        border: Border.all(
          color: Colors.black.withValues(
            alpha: _outlineOpacity * (1 - solid),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(
              alpha: _shadowOpacity * (1 - solid),
            ),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}
