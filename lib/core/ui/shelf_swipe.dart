import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The one-finger gestures a zoomable shelf surface owns — swipe, hold, and
/// the downward throw that dismisses a fullscreen view.
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
/// [onHold] is here for exactly that reason and not because a hold is a kind of
/// swipe. A `GestureDetector`'s long press would take the pinch away in the
/// same manner the drag did — it declares victory on a *still* finger after
/// 500ms, which is precisely the finger that is waiting for a second one to
/// land — and it would do it on the two surfaces that had the bug. Measured off
/// the same pointer stream it cannot, and the two gestures share one state
/// machine, so a finger can never both copy the image and turn the page.
///
/// The dismiss is here for the third time on the same argument. A
/// `VerticalDragGestureRecognizer` would sweep the arena the instant a finger
/// crossed slop downward and the pinch would be gone with it — the very bug
/// measured on the SM-X730. Measured off the same pointer stream it cannot,
/// and the room was already free: the swipe has always discarded travel
/// that is more vertical than horizontal, so nothing here read a downward drag
/// at all. It stays disarmed while [isZoomed], where a vertical drag is a pan
/// across a magnified image and nothing else.
///
/// ```dart
/// ShelfSwipe(
///   isZoomed: zoom.isZoomed,
///   onNext: gallery.canSelectNext ? gallery.selectNext : null,
///   onHold: () => copy(wallpaper),
///   onDragDown: (double dy) => setState(() => _dismissDrag = dy),
///   onDismiss: close,
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
    this.onHold,
    this.onDragDown,
    this.onDismiss,
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

  /// Called when one finger has rested on a fitted image for
  /// [holdDuration] without travelling. Null leaves the gesture unarmed,
  /// which is how a surface withholds it — an explicit wallpaper may not be
  /// copied, so it is simply never offered the hold.
  ///
  /// Fires a haptic tick of its own the moment it registers. A hold has no
  /// visual state to change and its work can take a moment, so without one the
  /// user has no way to tell a registered hold from a missed one. It is never
  /// the *only* way to reach whatever it does: a gesture is invisible to a
  /// screen reader, so the surfaces using it keep a labelled control too.
  final VoidCallback? onHold;

  /// Reports how far a downward throw has travelled, for a surface that wants
  /// to follow the finger — the fullscreen viewer slides and fades its canvas
  /// by this. Called with zero when the throw is released short of
  /// [dismissThreshold] and the surface should spring back.
  ///
  /// Only ever downward, and only while the gesture is more vertical than
  /// horizontal: a sideways drag is a page turn and must not drag the picture
  /// off the screen on its way.
  final ValueChanged<double>? onDragDown;

  /// Called when a downward throw is released past [dismissThreshold].
  ///
  /// Null leaves the gesture unarmed, which is what every surface that is not
  /// a fullscreen route passes — a shelf tile has nothing to dismiss.
  final VoidCallback? onDismiss;

  /// How far a finger must travel horizontally before it counts as a swipe.
  ///
  /// Wide enough that steadying a thumb on the image, or starting a pinch that
  /// never got its second finger down, does not turn the page.
  static const double swipeThreshold = 64;

  /// How long a still finger must stay down to count as a hold — the
  /// platform's own long-press timeout, so it feels like every other long press
  /// on the device rather than like a number tela picked.
  static const Duration holdDuration = kLongPressTimeout;

  /// How far a finger must travel downward before releasing it dismisses.
  ///
  /// Deliberately larger than [swipeThreshold]: a page turn that misfires
  /// costs one swipe back, while a dismiss that misfires throws the user out
  /// of the screen they were reading. The asymmetry is the point.
  static const double dismissThreshold = 120;

  @override
  State<ShelfSwipe> createState() => _ShelfSwipeState();
}

class _ShelfSwipeState extends State<ShelfSwipe> {
  int _pointers = 0;
  Offset? _start;
  Offset? _latest;
  Timer? _hold;
  int? _held;
  bool _dragging = false;

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

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

  /// Arms both gestures, and only for a lone finger on a fitted image. A second
  /// finger is a pinch, and disarming here is what stops the pinch's own drift
  /// from being read as a page turn when it ends — or its stillness, while the
  /// second finger is on its way down, from being read as a hold.
  void _startSwipe(PointerDownEvent event) {
    _pointers++;
    _cancelHold();
    if (_pointers != 1 || widget.isZoomed) {
      _start = null;
      return;
    }
    _start = event.localPosition;
    _latest = event.localPosition;
    _held = event.pointer;
    _armHold();
  }

  /// Tracks the travel, and drops the hold as soon as the finger is going
  /// somewhere: a swipe that happens to be slow is still a swipe.
  void _updateSwipe(PointerMoveEvent event) {
    final Offset? start = _start;
    if (_pointers != 1 || start == null) return;
    _latest = event.localPosition;
    final Offset travel = event.localPosition - start;
    if (travel.distance > kTouchSlop) _cancelHold();
    _reportDragDown(travel);
  }

  /// Follows a downward throw while it is still in the finger.
  ///
  /// The same rule [_selectAcross] applies, and for the same reason: a gesture
  /// is only a dismiss while it is more vertical than horizontal, so a diagonal
  /// that resolves into a page turn never drags the picture with it. Crossing
  /// back over that line, or upward, reports zero and springs the surface back.
  void _reportDragDown(Offset travel) {
    final ValueChanged<double>? report = widget.onDragDown;
    if (report == null || widget.onDismiss == null) return;
    final bool dismissing =
        travel.dy > kTouchSlop && travel.dy.abs() > travel.dx.abs();
    if (!dismissing && !_dragging) return;
    _dragging = dismissing;
    report(dismissing ? travel.dy : 0);
  }

  void _armHold() {
    if (widget.onHold == null) return;
    _hold = Timer(ShelfSwipe.holdDuration, _fireHold);
  }

  /// Fires the hold and takes the pointer sequence away from everyone else.
  ///
  /// Disarming the swipe is not enough. This widget leaves the arena alone by
  /// design, so the viewport's own tap recognizer is still holding the finger
  /// and — measured, not assumed — a [TapGestureRecognizer] has no upper time
  /// limit: it fires `onTap` on the way up however long the finger sat there.
  /// The fullscreen viewer toggles its chrome on that tap, so without the
  /// cancel a hold would copy the image *and* hide the controls. One finger
  /// does one thing.
  void _fireHold() {
    _hold = null;
    _start = null;
    final int? pointer = _held;
    unawaited(HapticFeedback.mediumImpact());
    if (pointer != null) GestureBinding.instance.cancelPointer(pointer);
    widget.onHold?.call();
  }

  void _cancelHold() {
    _hold?.cancel();
    _hold = null;
  }

  /// Turns the page on the *last* finger up, and only if the whole gesture was
  /// one finger travelling mostly sideways.
  void _finishSwipe(PointerUpEvent event) {
    final Offset? start = _start;
    final Offset end = _latest ?? event.localPosition;
    final bool wasDragging = _dragging;
    _releasePointer();
    if (_pointers != 0 || start == null || widget.isZoomed) return;
    if (_dismissAcross(end - start, wasDragging)) return;
    _selectAcross(end - start);
  }

  void _cancelSwipe(PointerCancelEvent event) {
    if (_dragging) widget.onDragDown?.call(0);
    _releasePointer();
  }

  void _releasePointer() {
    if (_pointers > 0) _pointers--;
    _cancelHold();
    _start = null;
    _latest = null;
    _held = null;
    _dragging = false;
  }

  /// Commits or abandons a downward throw, and reports which by returning
  /// whether the gesture was one at all — a throw that fell short still
  /// belonged to the dismiss, so it springs back rather than turning a page.
  bool _dismissAcross(Offset travel, bool wasDragging) {
    if (!wasDragging) return false;
    if (travel.dy >= ShelfSwipe.dismissThreshold) {
      widget.onDismiss?.call();
      return true;
    }
    widget.onDragDown?.call(0);
    return true;
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
