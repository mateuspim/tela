import 'package:flutter/material.dart';

/// A one-finger horizontal swipe that never enters the gesture arena.
///
/// Every zoomable gallery surface in tela has the same problem: an
/// [InteractiveViewer] and a page-turning drag both want the same fingers, and
/// a recognizer contest between them is one the pinch loses. A horizontal drag
/// recognizer accepts the moment the *first* finger
/// crosses touch slop, the arena is swept, and the scale recognizer is thrown
/// out for the rest of that pointer sequence — so the second finger arrives to
/// a gesture that has already been decided, and the pinch reads as a one-finger
/// swipe. Measured on the SM-X730 and reproduced in
/// `detail_preview_pager_test.dart`: fingers landing together zoomed fine,
/// fingers landing a moment apart did not move the scale off 1.0 at all.
///
/// So paging here is not a recognizer. A [Listener] sees raw pointer events
/// without competing for them, measures the swipe itself, and leaves the arena
/// to the viewport — which is why the fullscreen viewer's zoom was always solid
/// while Detail's was not. Detail now pages the same way.
///
/// ```dart
/// ShelfSwipe(
///   isZoomed: zoom.isZoomed,
///   onNext: gallery.canSelectNext ? gallery.selectNext : null,
///   child: viewport,
/// )
/// ```
class ShelfSwipe extends StatefulWidget {
  /// Wraps [child] in swipe-to-page without taking any gesture from it.
  const ShelfSwipe({
    required this.child,
    required this.isZoomed,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  /// The surface being swiped across, usually a zoomable viewport.
  final Widget child;

  /// Whether the image is magnified, in which case a drag is a pan across it
  /// and must not change the selection.
  final bool isZoomed;

  /// Selects the previous item. Null at a loaded boundary, which makes the
  /// swipe a no-op rather than a silent failure.
  final VoidCallback? onPrevious;

  /// Selects the next item. Null at a loaded boundary.
  final VoidCallback? onNext;

  /// How far a finger must travel horizontally before it counts as a swipe.
  ///
  /// Wide enough that steadying a thumb on the image, or starting a pinch that
  /// never got its second finger down, does not turn the page.
  static const double swipeThreshold = 64;

  @override
  State<ShelfSwipe> createState() => _ShelfSwipeState();
}

class _ShelfSwipeState extends State<ShelfSwipe> {
  int _pointers = 0;
  Offset? _start;
  Offset? _latest;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _startSwipe,
      onPointerMove: _updateSwipe,
      onPointerUp: _finishSwipe,
      onPointerCancel: _cancelSwipe,
      child: widget.child,
    );
  }

  /// Arms the swipe only for a lone finger on a fitted image. A second finger
  /// is a pinch, and disarming here is what stops the pinch's own drift from
  /// being read as a page turn when it ends.
  void _startSwipe(PointerDownEvent event) {
    _pointers++;
    if (_pointers != 1 || widget.isZoomed) {
      _start = null;
      return;
    }
    _start = event.localPosition;
    _latest = event.localPosition;
  }

  void _updateSwipe(PointerMoveEvent event) {
    if (_pointers == 1 && _start != null) _latest = event.localPosition;
  }

  /// Turns the page on the *last* finger up, and only if the whole gesture was
  /// one finger travelling mostly sideways.
  void _finishSwipe(PointerUpEvent event) {
    final Offset? start = _start;
    final Offset end = _latest ?? event.localPosition;
    _releasePointer();
    if (_pointers != 0 || start == null || widget.isZoomed) return;
    _selectAcross(end - start);
  }

  void _cancelSwipe(PointerCancelEvent event) => _releasePointer();

  void _releasePointer() {
    if (_pointers > 0) _pointers--;
    _start = null;
    _latest = null;
  }

  /// Reads a direction out of [travel], ignoring anything too short or more
  /// vertical than horizontal — a scroll of the screen underneath is not a
  /// page turn.
  void _selectAcross(Offset travel) {
    if (travel.dx.abs() < ShelfSwipe.swipeThreshold) return;
    if (travel.dx.abs() <= travel.dy.abs()) return;
    if (travel.dx < 0) {
      widget.onNext?.call();
    } else {
      widget.onPrevious?.call();
    }
  }
}
