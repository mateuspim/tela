import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Publishes how far a screen's scenery should have drifted from centre.
///
/// Parallax on the browse wall was refused — it needs the image taller than its
/// box, and `justified_rows.dart` promises three times over that nothing is
/// cropped. Detail's letterbox backdrop is `BoxFit.cover` by construction, so
/// drifting *that* costs no law. This is the wire between the two halves: the
/// layout that owns the gesture publishes a value here, and
/// `BlurredImageBackdrop` reads it wherever it happens to be mounted.
///
/// A scope rather than a constructor parameter because the backdrop is built
/// three widgets down — the screen hands a page to `DetailPreviewPager`, which
/// hands a wallpaper to `ProgressiveWallpaperPreview`, which is what actually
/// constructs the backdrop. Threading a listenable through both would give the
/// pager a concern that is not its own.
///
/// [drift] runs -1..1, where 0 is centred, negative is up, and ±1 is the whole
/// travel the backdrop has room for. It is a *listenable* and not a value so
/// that a drag repaints the scenery alone; rebuilding this scope every frame
/// would rebuild the preview under it.
///
/// No scope above means no drift, which is what the immersive viewer, the crop
/// editor and every widget test that mounts a backdrop on its own get.
///
/// ```dart
/// BackdropDriftScope(drift: _drift, child: body); // _drift: ValueNotifier<double>
/// BackdropDriftScope.maybeOf(context); // the listenable, or null
/// ```
class BackdropDriftScope extends InheritedWidget {
  /// Publishes [drift] to every backdrop under [child].
  const BackdropDriftScope({
    required this.drift,
    required super.child,
    super.key,
  });

  /// How far the scenery has travelled, -1..1, from the surface that moves it.
  final ValueListenable<double> drift;

  /// The drift in force at [context], or null with no scope above it.
  static ValueListenable<double>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BackdropDriftScope>()
        ?.drift;
  }

  @override
  bool updateShouldNotify(BackdropDriftScope oldWidget) =>
      oldWidget.drift != drift;
}
