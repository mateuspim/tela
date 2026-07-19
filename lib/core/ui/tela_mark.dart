import 'package:flutter/material.dart';
import 'package:tela/app/theme.dart';

/// tela's mark: four bands in a cyclic interlace, drawn as a square frame.
///
/// The brand's one non-typographic signature, and the twin of `TelaWordmark` —
/// a widget rather than a scattered painter so the rail, the launcher icon and
/// anything else that shows the mark get the same lockup, not a near-miss.
///
/// It is drawn rather than shipped as an image: the shape is four rounded
/// rectangles, and pulling in a vector-rendering package for that would earn a
/// port under this project's wrapping rule for nothing.
///
/// Decorative by default, so the wordmark beside it is the only thing a screen
/// reader announces; pass [semanticLabel] where the mark stands alone.
///
/// ```dart
/// const TelaMark(size: 28);
/// ```
class TelaMark extends StatelessWidget {
  /// Creates the mark at [size] square, optionally in [color].
  const TelaMark({this.size = 24, this.color, this.semanticLabel, super.key});

  /// The mark's width and height. It is always square.
  final double size;

  /// Overrides the default [TelaTheme.brandSeed] ink — for a mark sitting on
  /// an image, or a single-colour context.
  final Color? color;

  /// Names the mark for a screen reader. Leave null where the wordmark or a
  /// heading already says "tela"; a mark that announces itself beside one is a
  /// duplicate node.
  final String? semanticLabel;

  /// The design grid the geometry is expressed on — the adaptive-icon canvas,
  /// so `assets/brand/tela_mark.svg` and the Android drawables use these exact
  /// numbers with nothing to re-derive.
  static const double gridExtent = 108;

  /// Outer edge of the frame on [gridExtent], and its opposite edge.
  ///
  /// The half-extent this implies (25) is bounded by the launcher's *circular*
  /// mask, not the 72dp safe square: a square inscribed in that circle has a
  /// half-extent of only 36/sqrt(2). See `docs/BRAND.md`.
  static const double frameStart = 29;

  /// The frame's far edge on [gridExtent]. See [frameStart].
  static const double frameEnd = 79;

  /// How much of [gridExtent] the mark actually inks.
  ///
  /// Under half, and that is the launcher's business, not ours: the rest is the
  /// clearance a mask needs. In a widget there is no mask, so [TelaMarkPainter]
  /// scales *this* onto the box it is given rather than [gridExtent] — [size]
  /// means the mark, not a canvas with the icon's padding baked into it.
  static const double frameExtent = frameEnd - frameStart;

  /// Width of a band on [gridExtent]. Its ends are pills, radius [bandWidth]/2.
  static const double bandWidth = 12;

  /// Clearance left around the band passing *over*, on [gridExtent].
  ///
  /// This gap is the whole interlace. It is a cut and not a tone because
  /// Material You's themed icon discards colour and tints one flat silhouette —
  /// shade the crossings instead and the mark becomes a closed square there.
  static const double cutMargin = 2.75;

  @override
  Widget build(BuildContext context) {
    final Widget mark = CustomPaint(
      size: Size.square(size),
      painter: TelaMarkPainter(color ?? TelaTheme.brandSeed),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

/// Paints the four interlaced bands, scaled from the [TelaMark.gridExtent]
/// design grid onto whatever square it is given.
///
/// Public because the mark is sometimes wanted on a canvas rather than in a
/// widget tree, and because it is what a test can inspect to see the ink that
/// was actually used.
///
/// ```dart
/// TelaMarkPainter(TelaTheme.brandSeed).paint(canvas, const Size.square(108));
/// ```
class TelaMarkPainter extends CustomPainter {
  /// Paints every band in [color].
  const TelaMarkPainter(this.color);

  /// Ink for every band. The mark is one colour in Flutter: the two-tone
  /// warp/weft split exists only on the launcher icon, which has a ground of
  /// its own to sit the lighter tint against.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Scaled to the frame, not the whole design grid: the grid's outer margin
    // is clearance for a launcher mask, and honouring it in a widget would draw
    // a mark half the size the caller asked for. See TelaMark.frameExtent.
    final double unit = size.shortestSide / TelaMark.frameExtent;
    final Paint brush = Paint()..color = color;
    for (final RRect band in _bands()) {
      canvas.drawRRect(_scaled(band, unit), brush);
    }
  }

  /// The four bands on the design grid: top, bottom, left, right.
  ///
  /// Each is shortened at the end that passes *under* its neighbour, in a
  /// cycle — top under right, right under bottom, bottom under left, left
  /// under top — which is what makes the mark symmetric under a half turn.
  List<RRect> _bands() {
    const double a = TelaMark.frameStart;
    const double b = TelaMark.frameEnd;
    const double w = TelaMark.bandWidth;
    const double cut = w + TelaMark.cutMargin;
    const Radius pill = Radius.circular(w / 2);
    return <RRect>[
      RRect.fromLTRBR(a, a, b - cut, a + w, pill), // top, under right
      RRect.fromLTRBR(a + cut, b - w, b, b, pill), // bottom, under left
      RRect.fromLTRBR(a, a + cut, a + w, b, pill), // left, under top
      RRect.fromLTRBR(b - w, a, b, b - cut, pill), // right, under bottom
    ];
  }

  /// Scales a band from the design grid onto the painted square, shifting the
  /// frame's own origin to the box's corner.
  RRect _scaled(RRect band, double unit) {
    const double origin = TelaMark.frameStart;
    return RRect.fromLTRBR(
      (band.left - origin) * unit,
      (band.top - origin) * unit,
      (band.right - origin) * unit,
      (band.bottom - origin) * unit,
      Radius.circular(band.tlRadiusX * unit),
    );
  }

  @override
  bool shouldRepaint(TelaMarkPainter oldDelegate) => oldDelegate.color != color;
}
