import 'package:flutter/material.dart';

/// The wash that keeps the status bar readable over a bright wallpaper on
/// Detail. A [Positioned], so it goes straight into the body's [Stack].
///
/// ```dart
/// Stack(children: <Widget>[picture, const DetailTopScrim()]);
/// ```
class DetailTopScrim extends StatelessWidget {
  /// Creates the wash; place it in a [Stack] over the picture.
  const DetailTopScrim({super.key});

  /// Height of the wash behind the app bar's controls.
  ///
  /// A transparent bar over an arbitrary photograph is a back arrow that
  /// vanishes on a pale sky. This is the same argument as `wallpaperTileEdge`
  /// and it is *not* the frosted bar A2 rejected: nothing is blurred, nothing
  /// shows a wall of thumbnails through itself, and there is exactly one image
  /// underneath rather than sixty.
  ///
  /// Shortened from 148 once the bar's controls moved into `PhotoCapsule`s
  /// (2026-10-05): they carry their own scrim, so the wash no longer has to
  /// reach down past them — see [opacity].
  static const double height = 112;

  /// How far down the wash the app bar's own controls sit.
  ///
  /// It was the status bar plus half a toolbar — where the bare back arrow
  /// and actions were drawn. Those sit in capsules now, so the wash holds
  /// only over the status bar, whose white clock still has nothing else
  /// behind it.
  static const double controlRow = 40;

  /// The wash's opacity at the top edge and where it finally reaches zero.
  ///
  /// It **holds** at full strength down to [controlRow] instead of
  /// fading from the first pixel, which is the whole fix: a straight ramp
  /// spends most of its darkness above the controls, where there is nothing to
  /// read, and arrives at them already half gone. Measured on the device
  /// (SM-X730, 2026-08-14) against a genuinely pale wallpaper, the old ramp
  /// left the white controls at **2.9:1** — over the 3:1 floor for UI graphics
  /// by nothing. Holding the wash rather than steepening it buys the contrast
  /// without making the top edge of every wallpaper darker than it already is.
  ///
  /// **Lightened from 0.6 to 0.45 (owner, 2026-10-05)**, once the controls
  /// moved into `PhotoCapsule`s that bring their own contrast: 0.6 was muddying
  /// the top of every pale wallpaper for icons that no longer needed it. What
  /// is left is for the system status bar — white text over a near-white sky
  /// at 0.45 black still lands near 3.7:1, over the 3:1 floor.
  static const double opacity = 0.45;

  /// The wash's opacity [dip] logical pixels below the top of the screen.
  ///
  /// ```dart
  /// DetailTopScrim.alphaAt(0); // 0.45, full strength
  /// ```
  static double alphaAt(double dip) {
    if (dip <= controlRow) return opacity;
    if (dip >= height) return 0;
    final double fade = (dip - controlRow) / (height - controlRow);
    return opacity * (1 - fade);
  }

  /// Where the wash stops holding, as a fraction of its own height.
  static const double _controlRowStop = controlRow / height;

  /// The held colour, and the nothing it fades to.
  static const Color _wash = Color.fromRGBO(
    0,
    0,
    0,
    opacity,
  );
  static const Color _clear = Color.fromRGBO(0, 0, 0, 0);

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      // Decoration only: the image beneath it still takes every gesture, so
      // the wallpaper can be pinched and held right up to the top edge.
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Three stops, not two: full strength down past the controls,
              // then out. See alphaAt.
              stops: <double>[0, _controlRowStop, 1],
              colors: <Color>[_wash, _wash, _clear],
            ),
          ),
        ),
      ),
    );
  }
}
