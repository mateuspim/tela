import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Publishes how far Detail's facts sheet has risen, and how far that has
/// bumped the wallpaper, to the controls drawn over the picture.
///
/// The controls live inside `DetailPreviewPager`, which `DetailEditorialBody`
/// translates up as the sheet rises. Riding along, the fullscreen button left
/// the screen and the page arrows clipped into half-circles at the top edge
/// (device survey, SM-X730, 2026-10-05). Pinning one and fading both needs the
/// sheet's position, which only the body knows — the same wiring problem
/// `BackdropDriftScope` solves for the scenery, and solved the same way.
///
/// No scope above means a sheet at rest at the peek: nothing lifted, every
/// control shown — what the fullscreen viewer and lone widget tests get.
///
/// ```dart
/// DetailSheetProgress(lift: _lift, risen: _risen, child: body);
/// DetailSheetProgress.maybeOf(context)?.risen;
/// ```
class DetailSheetProgress extends InheritedWidget {
  /// Publishes [lift] and [risen] to everything under [child].
  const DetailSheetProgress({
    required this.lift,
    required this.risen,
    required super.child,
    super.key,
  });

  /// How far the wallpaper is bumped up, as a fraction of the body's height.
  final ValueListenable<double> lift;

  /// How far the sheet has travelled from the peek to full, 0..1.
  final ValueListenable<double> risen;

  /// The progress in force at [context], or null with no scope above it.
  static DetailSheetProgress? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DetailSheetProgress>();
  }

  @override
  bool updateShouldNotify(DetailSheetProgress oldWidget) =>
      oldWidget.lift != lift || oldWidget.risen != risen;
}
