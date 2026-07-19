import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays children out in [columnCount] columns, each child dropped into
/// whichever column is currently shortest.
///
/// A static split — "these three go left, those three go right" — leaves one
/// column ending far above the other, and inside a single scroll view that
/// short column becomes dead space you scroll past to read the tall one's tail.
/// Measuring instead means the columns end together whatever the children
/// weigh, and it does not re-break when one of them grows.
///
/// Children keep their source order *within* a column, but reading order across
/// the columns is not source order — so use this only for independent blocks
/// (settings groups), never for a sequence.
///
/// ```dart
/// BalancedColumns(
///   columnCount: 2,
///   spacing: 16,
///   children: <Widget>[accountGroup, appearanceGroup, storageGroup],
/// )
/// ```
class BalancedColumns extends MultiChildRenderObjectWidget {
  /// Creates a balanced column flow.
  const BalancedColumns({
    required this.columnCount,
    required this.spacing,
    required super.children,
    super.key,
  }) : assert(columnCount > 0, 'columnCount must be positive');

  /// How many columns to spread the children across.
  final int columnCount;

  /// The gap between two columns, and between two children in one column.
  final double spacing;

  @override
  RenderBalancedColumns createRenderObject(BuildContext context) {
    return RenderBalancedColumns(columnCount: columnCount, spacing: spacing);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBalancedColumns renderObject,
  ) {
    renderObject
      ..columnCount = columnCount
      ..spacing = spacing;
  }
}

/// Parent data holding each child's resolved offset.
class BalancedColumnsParentData extends ContainerBoxParentData<RenderBox> {}

/// The render box behind [BalancedColumns].
class RenderBalancedColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, BalancedColumnsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, BalancedColumnsParentData> {
  /// Creates the render box.
  RenderBalancedColumns({required int columnCount, required double spacing})
    : _columnCount = columnCount,
      _spacing = spacing;

  int _columnCount;
  double _spacing;

  /// How many columns to spread the children across.
  int get columnCount => _columnCount;
  set columnCount(int value) {
    if (_columnCount == value) return;
    _columnCount = value;
    markNeedsLayout();
  }

  /// The gap between two columns, and between two children in one column.
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BalancedColumnsParentData) {
      child.parentData = BalancedColumnsParentData();
    }
  }

  @override
  void performLayout() {
    size = _pack(constraints, dry: false);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _pack(constraints, dry: true);
  }

  /// Measures every child at the column width and assigns it to the shortest
  /// column so far, returning the size the whole flow needs.
  ///
  /// Ties go to the leftmost column, so a first row of equal-height children
  /// still reads left to right.
  Size _pack(BoxConstraints constraints, {required bool dry}) {
    final double width = constraints.maxWidth;
    final BoxConstraints childConstraints = _childConstraints(width);
    final List<double> heights = List<double>.filled(columnCount, 0);
    RenderBox? child = firstChild;
    while (child != null) {
      final Size childSize = _measure(child, childConstraints, dry: dry);
      final int column = _shortestColumn(heights);
      if (!dry) _place(child, column, heights[column], childConstraints);
      heights[column] += childSize.height + spacing;
      child = childAfter(child);
    }
    return Size(width, math.max(0, heights.reduce(math.max) - spacing));
  }

  BoxConstraints _childConstraints(double width) {
    final double columnWidth =
        (width - spacing * (columnCount - 1)) / columnCount;
    return BoxConstraints.tightFor(width: math.max(0, columnWidth));
  }

  Size _measure(
    RenderBox child,
    BoxConstraints childConstraints, {
    required bool dry,
  }) {
    if (dry) return child.getDryLayout(childConstraints);
    child.layout(childConstraints, parentUsesSize: true);
    return child.size;
  }

  void _place(
    RenderBox child,
    int column,
    double top,
    BoxConstraints childConstraints,
  ) {
    (child.parentData! as BalancedColumnsParentData).offset = Offset(
      column * (childConstraints.maxWidth + spacing),
      top,
    );
  }

  int _shortestColumn(List<double> heights) {
    int shortest = 0;
    for (int column = 1; column < heights.length; column++) {
      if (heights[column] < heights[shortest]) shortest = column;
    }
    return shortest;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => double.infinity;

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
