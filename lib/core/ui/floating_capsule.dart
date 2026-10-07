import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// An opaque, raised surface that tela's chrome floats in: the search capsule,
/// the action cluster, the sorting track, the navigation pill and rail.
///
/// **Opaque by contract, never glass.** Frosted chrome over the wall was built
/// and rejected on device in pass A2 — the thumbnails showed through the search
/// bar. What makes this read as floating is shape, a hairline edge and a soft
/// shadow on a solid band, not translucency; `floating_capsule_test.dart` fails
/// if the fill is ever made see-through.
///
/// A null [radius] is a stadium (fully rounded ends), the shape for one-line
/// controls; a panel taller than a line passes a radius.
///
/// ```dart
/// FloatingCapsule(child: BrowseSearchField());
/// FloatingCapsule(radius: 28, child: Column(children: <Widget>[...]));
/// ```
class FloatingCapsule extends StatelessWidget {
  /// Creates a capsule around [child].
  const FloatingCapsule({
    required this.child,
    this.radius,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// What floats in the capsule.
  final Widget child;

  /// Corner radius; null for a stadium.
  final double? radius;

  /// Space between the capsule's edge and [child].
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return CapsuleSurface(
      fill: capsuleFill(scheme),
      edge: scheme.outlineVariant.withValues(alpha: .45),
      shadows: _shadows(scheme),
      radius: radius,
      padding: padding,
      child: child,
    );
  }

  /// The capsule's fill on [scheme] — the most raised surface the scheme has.
  ///
  /// It must sit well above the band's top stop (`surfaceContainer` warmed
  /// with the brand), and stays above even `surfaceContainerHighest`. In dark
  /// the raised end of the tonal range is `surfaceBright`; in light it is the
  /// near-white `surfaceContainerLowest`. Tuned on the SM-X730 (2026-10-05),
  /// which also showed these roles need `TelaTheme`'s Monet surface fill to
  /// differ from `surface` at all.
  ///
  /// Forced opaque: a device palette is opaque already, so this only guards
  /// against a future scheme edit quietly turning the chrome into glass.
  static Color capsuleFill(ColorScheme scheme) {
    final bool dark = scheme.brightness == Brightness.dark;
    final Color raised = dark
        ? scheme.surfaceBright
        : scheme.surfaceContainerLowest;
    return raised.withValues(alpha: 1);
  }

  /// A low, wide shadow: lift without a hard drop edge. Weaker in light mode,
  /// where a dark shadow on a pale band reads as dirt.
  List<BoxShadow> _shadows(ColorScheme scheme) {
    final bool dark = scheme.brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? .32 : .10),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];
  }
}

/// The shape, edge, shadow and clip every tela capsule is drawn with, given
/// its [fill] — the one part that differs between [FloatingCapsule] (opaque,
/// on the band) and `PhotoCapsule` (a scrim, over a single photograph).
///
/// ```dart
/// CapsuleSurface(fill: fill, edge: edge, shadows: shadows, child: child);
/// ```
class CapsuleSurface extends StatelessWidget {
  /// Creates the surface around [child].
  const CapsuleSurface({
    required this.fill,
    required this.edge,
    required this.shadows,
    required this.child,
    this.radius,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// The capsule's body colour.
  final Color fill;

  /// The hairline drawn around it.
  final Color edge;

  /// The lift under it.
  final List<BoxShadow> shadows;

  /// What sits in the capsule.
  final Widget child;

  /// Corner radius; null for a stadium.
  final double? radius;

  /// Space between the capsule's edge and [child].
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ShapeBorder shape = _shape();
    return DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: shape, shadows: shadows),
      // Clipped to the shape so an ink splash or a tab indicator cannot
      // square off the rounded ends.
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  ShapeBorder _shape() {
    final BorderSide side = BorderSide(color: edge);
    final double? r = radius;
    if (r == null) return StadiumBorder(side: side);
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(r),
      side: side,
    );
  }
}

/// App-bar actions gathered into one [FloatingCapsule], so a row of icons
/// reads as one control group instead of three unrelated treatments.
///
/// Collapses to nothing when every action renders nothing. The app bar stays
/// up while a screen is selecting, and actions like `SelectModeButton` hide
/// themselves then — without the collapse, a screen whose actions all hid
/// would be left with an empty pill.
///
/// ```dart
/// AppBar(actions: <Widget>[
///   CapsuleActionCluster(children: <Widget>[SelectModeButton(), filters]),
/// ]);
/// ```
class CapsuleActionCluster extends StatelessWidget {
  /// Creates the cluster around [children], left to right.
  const CapsuleActionCluster({required this.children, super.key});

  /// The actions, normally icon buttons.
  final List<Widget> children;

  /// Space between the capsule's edge and the actions.
  static const double inset = 4;

  /// The screen width from which a cluster action may spell itself out
  /// ("Wallhaven ▾", "Latest ▾"). Below it every action is a 48dp icon, named
  /// by its tooltip: two labels pushed a phone's cluster past the bar and
  /// squeezed the search field beside it to nothing (2026-10-06).
  static const double labelledWidth = 600;

  /// Whether this screen is wide enough for labelled actions; see
  /// [labelledWidth].
  ///
  /// ```dart
  /// if (CapsuleActionCluster.labels(context)) return Text(name);
  /// ```
  static bool labels(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= labelledWidth;

  @override
  Widget build(BuildContext context) {
    return _CollapseWhenEmpty(
      emptyWidth: inset * 2,
      child: FloatingCapsule(
        padding: const EdgeInsets.all(inset),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Takes no space and paints nothing when its child is no wider than
/// [emptyWidth] — a capsule holding only its own padding.
class _CollapseWhenEmpty extends SingleChildRenderObjectWidget {
  const _CollapseWhenEmpty({required this.emptyWidth, required super.child});

  final double emptyWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCollapseWhenEmpty(emptyWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCollapseWhenEmpty renderObject,
  ) {
    renderObject.emptyWidth = emptyWidth;
  }
}

class _RenderCollapseWhenEmpty extends RenderProxyBox {
  _RenderCollapseWhenEmpty(this._emptyWidth);

  double _emptyWidth;
  bool _collapsed = false;

  double get emptyWidth => _emptyWidth;
  set emptyWidth(double value) {
    if (value == _emptyWidth) return;
    _emptyWidth = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final RenderBox? box = child;
    if (box == null) {
      size = constraints.smallest;
      return;
    }
    box.layout(constraints, parentUsesSize: true);
    _collapsed = box.size.width <= _emptyWidth;
    size = _collapsed ? constraints.smallest : box.size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final Size measured = super.computeDryLayout(constraints);
    return measured.width <= _emptyWidth ? constraints.smallest : measured;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_collapsed) super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_collapsed && super.hitTest(result, position: position);
}

/// A full-width [FloatingCapsule] track for an app bar's `bottom` — the
/// sorting tabs ride on it as one segmented control.
///
/// Reports [child]'s height plus its own inset and gap, so the app bar
/// reserves exactly what is drawn.
///
/// ```dart
/// AppBar(bottom: CapsuleTrack(child: TabBar(tabs: tabs)));
/// ```
class CapsuleTrack extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the track around [child].
  const CapsuleTrack({required this.child, super.key});

  /// What rides the track, normally a scrollable [TabBar].
  final PreferredSizeWidget child;

  /// Space between the track's edge and [child].
  static const double inset = 4;

  /// Margin around the track: the band's side gutter, and air below it.
  static const EdgeInsets margin = EdgeInsets.fromLTRB(16, 4, 16, 12);

  @override
  Size get preferredSize => Size.fromHeight(
    child.preferredSize.height + inset * 2 + margin.vertical,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: FloatingCapsule(
        padding: const EdgeInsets.all(inset),
        child: child,
      ),
    );
  }
}
