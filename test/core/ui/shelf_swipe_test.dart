import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/shelf_swipe.dart';

/// Pins the rules the fullscreen viewer had carried inline since slice 3, now
/// that Detail's pager depends on the same widget for all of its paging.
///
/// The one that is not obvious is the two-finger case: a pinch drifts, and if
/// that drift were read as a swipe the page would turn out from under a zoom
/// the user was still setting up.
///
/// The hold tests below guard the same arena from the other side. A hold is
/// measured here rather than by a `GestureDetector` precisely so it cannot take
/// the pinch the way the pager's drag once did, and the cases that matter are
/// the ones where a hold must *not* fire: a finger on its way somewhere, and a
/// finger waiting for its partner to land.
void main() {
  testWidgets('a long sideways drag selects in the direction it travelled', (
    WidgetTester tester,
  ) async {
    final List<String> selected = <String>[];
    await _pumpSwipe(tester, selected: selected);

    await _drag(tester, const Offset(-120, 0));
    expect(selected, <String>['next']);

    await _drag(tester, const Offset(120, 0));
    expect(selected, <String>['next', 'previous']);
  });

  testWidgets('a drag under the threshold is not a page turn', (
    WidgetTester tester,
  ) async {
    // A thumb steadying itself on the image is not asking for anything.
    final List<String> selected = <String>[];
    await _pumpSwipe(tester, selected: selected);

    await _drag(tester, const Offset(-(ShelfSwipe.swipeThreshold - 8), 0));

    expect(selected, isEmpty);
  });

  testWidgets('a mostly vertical drag is not a page turn', (
    WidgetTester tester,
  ) async {
    // Detail scrolls under the preview; a scroll that clips the image must not
    // also change which wallpaper is being read about.
    final List<String> selected = <String>[];
    await _pumpSwipe(tester, selected: selected);

    await _drag(tester, const Offset(-100, -140));

    expect(selected, isEmpty);
  });

  testWidgets('a second finger cancels the swipe outright', (
    WidgetTester tester,
  ) async {
    // The pinch's own drift is not a page turn, even when it is long and
    // sideways — which is exactly what a pinch looks like.
    final List<String> selected = <String>[];
    await _pumpSwipe(tester, selected: selected);

    final Offset centre = tester.getCenter(find.byType(ShelfSwipe));
    final TestGesture left = await tester.startGesture(centre);
    final TestGesture right = await tester.startGesture(
      centre + const Offset(40, 0),
    );
    await left.moveBy(const Offset(-160, 0));
    await right.moveBy(const Offset(160, 0));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
  });

  testWidgets('a zoomed image is panned across, not paged', (
    WidgetTester tester,
  ) async {
    final List<String> selected = <String>[];
    await _pumpSwipe(tester, selected: selected, isZoomed: true);

    await _drag(tester, const Offset(-200, 0));

    expect(selected, isEmpty);
  });

  testWidgets('a swipe past the last item does nothing', (
    WidgetTester tester,
  ) async {
    // A boundary is expressed by a null callback, so the swipe is a no-op
    // rather than something the caller has to guard.
    final List<String> selected = <String>[];
    await _pumpSwipe(tester, selected: selected, atLastItem: true);

    await _drag(tester, const Offset(-200, 0));

    expect(selected, isEmpty);
  });

  testWidgets('a still finger past the timeout holds, and does not page', (
    WidgetTester tester,
  ) async {
    final List<String> selected = <String>[];
    final List<String> held = <String>[];
    await _pumpSwipe(tester, selected: selected, held: held);

    final TestGesture finger = await tester.startGesture(_centre(tester));
    await tester.pump(
      ShelfSwipe.holdDuration + const Duration(milliseconds: 8),
    );
    expect(held, <String>['held'], reason: 'the hold fires while still down');

    await finger.up();
    await tester.pumpAndSettle();

    // One finger does one thing: the hold consumed the gesture, so lifting it
    // must not also turn the page.
    expect(selected, isEmpty);
  });

  testWidgets('the hold ticks the device the moment it registers', (
    WidgetTester tester,
  ) async {
    // A hold changes nothing on screen and its work can take a moment, so the
    // haptic is the only thing telling the user it was heard.
    final List<String> haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pumpSwipe(tester, selected: <String>[], held: <String>[]);

    final TestGesture finger = await tester.startGesture(_centre(tester));
    await tester.pump(
      ShelfSwipe.holdDuration + const Duration(milliseconds: 8),
    );
    await finger.up();
    await tester.pumpAndSettle();

    expect(haptics, <String>['HapticFeedbackType.mediumImpact']);
  });

  testWidgets('the tap under the hold never fires', (
    WidgetTester tester,
  ) async {
    // The viewport's own tap recognizer is still holding this finger — this
    // widget stays out of the arena on purpose — and a TapGestureRecognizer has
    // no upper time limit, so it would fire on the way up. Fullscreen toggles
    // its chrome on that tap: without the cancel, a hold copies the image and
    // hides the controls.
    final List<String> held = <String>[];
    final List<String> tapped = <String>[];
    await _pumpSwipe(
      tester,
      selected: <String>[],
      held: held,
      onTap: () => tapped.add('tap'),
    );

    final TestGesture finger = await tester.startGesture(_centre(tester));
    await tester.pump(
      ShelfSwipe.holdDuration + const Duration(milliseconds: 8),
    );
    await finger.up();
    await tester.pumpAndSettle();

    expect(held, <String>['held']);
    expect(tapped, isEmpty);
  });

  testWidgets('a plain tap still reaches the image under it', (
    WidgetTester tester,
  ) async {
    final List<String> tapped = <String>[];
    await _pumpSwipe(
      tester,
      selected: <String>[],
      held: <String>[],
      onTap: () => tapped.add('tap'),
    );

    await tester.tap(find.byType(ShelfSwipe));
    await tester.pumpAndSettle();

    expect(tapped, <String>['tap']);
  });

  testWidgets('a finger lifted before the timeout does not hold', (
    WidgetTester tester,
  ) async {
    final List<String> held = <String>[];
    await _pumpSwipe(tester, selected: <String>[], held: held);

    final TestGesture finger = await tester.startGesture(_centre(tester));
    await tester.pump(
      ShelfSwipe.holdDuration - const Duration(milliseconds: 50),
    );
    await finger.up();
    await tester.pumpAndSettle();

    expect(held, isEmpty);
  });

  testWidgets('a travelling finger never holds, however slowly it goes', (
    WidgetTester tester,
  ) async {
    // A slow swipe is still a swipe. Without this, dragging across the image
    // for half a second would copy it and turn no page.
    final List<String> selected = <String>[];
    final List<String> held = <String>[];
    await _pumpSwipe(tester, selected: selected, held: held);

    final TestGesture finger = await tester.startGesture(_centre(tester));
    for (int step = 0; step < 8; step++) {
      await finger.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await finger.up();
    await tester.pumpAndSettle();

    expect(held, isEmpty);
    expect(selected, <String>['next'], reason: 'it was a swipe all along');
  });

  testWidgets('a second finger cancels the hold', (WidgetTester tester) async {
    // The pinch that waits for its partner: finger one lands and sits still,
    // which is exactly what a hold looks like until finger two arrives. A
    // recognizer would have already claimed the gesture by then; this must not.
    final List<String> held = <String>[];
    await _pumpSwipe(tester, selected: <String>[], held: held);

    final Offset centre = _centre(tester);
    final TestGesture first = await tester.startGesture(centre);
    await tester.pump(const Duration(milliseconds: 200));
    final TestGesture second = await tester.startGesture(
      centre + const Offset(40, 0),
    );
    await tester.pump(ShelfSwipe.holdDuration);
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(held, isEmpty);
  });

  testWidgets('a zoomed image is not held', (WidgetTester tester) async {
    // Zoomed, a resting finger is the start of a pan across the image. The
    // labelled Copy image control is still there for anyone who wants it.
    final List<String> held = <String>[];
    await _pumpSwipe(
      tester,
      selected: <String>[],
      held: held,
      isZoomed: true,
    );

    final TestGesture finger = await tester.startGesture(_centre(tester));
    await tester.pump(
      ShelfSwipe.holdDuration + const Duration(milliseconds: 8),
    );
    await finger.up();
    await tester.pumpAndSettle();

    expect(held, isEmpty);
  });

  testWidgets('without a hold callback the gesture is simply unarmed', (
    WidgetTester tester,
  ) async {
    // How a surface withholds it: an explicit wallpaper is passed no callback,
    // and nothing else about the swipe changes.
    final List<String> selected = <String>[];
    await _pumpSwipe(tester, selected: selected);

    final TestGesture finger = await tester.startGesture(_centre(tester));
    await tester.pump(
      ShelfSwipe.holdDuration + const Duration(milliseconds: 8),
    );
    await finger.moveBy(const Offset(-200, 0));
    await finger.up();
    await tester.pumpAndSettle();

    expect(selected, <String>['next']);
  });

  testWidgets('a long downward throw dismisses, and reports its travel', (
    WidgetTester tester,
  ) async {
    final List<double> dragged = <double>[];
    final List<String> dismissed = <String>[];
    await _pumpSwipe(
      tester,
      selected: <String>[],
      dragged: dragged,
      dismissed: dismissed,
    );

    await _drag(tester, const Offset(0, ShelfSwipe.dismissThreshold + 20));

    expect(dismissed, <String>['dismiss']);
    // The surface followed the finger on the way down rather than only
    // hearing about it at the end.
    expect(dragged, isNotEmpty);
    expect(dragged.last, greaterThan(0));
  });

  testWidgets('a throw that falls short springs back instead of dismissing', (
    WidgetTester tester,
  ) async {
    final List<double> dragged = <double>[];
    final List<String> dismissed = <String>[];
    await _pumpSwipe(
      tester,
      selected: <String>[],
      dragged: dragged,
      dismissed: dismissed,
    );

    await _drag(tester, const Offset(0, ShelfSwipe.dismissThreshold - 20));

    expect(dismissed, isEmpty);
    // Zero last, which is the instruction to spring back.
    expect(dragged.last, 0);
  });

  /// The dismiss threshold is deliberately larger than the swipe's: a page turn
  /// that misfires costs one swipe back, a dismiss that misfires throws the
  /// user out of the screen they were reading.
  testWidgets('a sideways drag turns the page without dragging the picture', (
    WidgetTester tester,
  ) async {
    final List<String> selected = <String>[];
    final List<double> dragged = <double>[];
    final List<String> dismissed = <String>[];
    await _pumpSwipe(
      tester,
      selected: selected,
      dragged: dragged,
      dismissed: dismissed,
    );

    await _drag(tester, const Offset(-140, 30));

    expect(selected, <String>['next']);
    expect(dismissed, isEmpty);
    expect(dragged, isEmpty);
  });

  testWidgets('a magnified image is panned downward, never dismissed', (
    WidgetTester tester,
  ) async {
    final List<double> dragged = <double>[];
    final List<String> dismissed = <String>[];
    await _pumpSwipe(
      tester,
      selected: <String>[],
      isZoomed: true,
      dragged: dragged,
      dismissed: dismissed,
    );

    await _drag(tester, const Offset(0, ShelfSwipe.dismissThreshold + 60));

    expect(dismissed, isEmpty);
    expect(dragged, isEmpty);
  });

  testWidgets('an upward drag is not a dismiss', (WidgetTester tester) async {
    final List<double> dragged = <double>[];
    final List<String> dismissed = <String>[];
    await _pumpSwipe(
      tester,
      selected: <String>[],
      dragged: dragged,
      dismissed: dismissed,
    );

    await _drag(tester, const Offset(0, -(ShelfSwipe.dismissThreshold + 60)));

    expect(dismissed, isEmpty);
    expect(dragged, isEmpty);
  });
}

Offset _centre(WidgetTester tester) =>
    tester.getCenter(find.byType(ShelfSwipe));

Future<void> _drag(WidgetTester tester, Offset travel) async {
  final TestGesture finger = await tester.startGesture(
    tester.getCenter(find.byType(ShelfSwipe)),
  );
  for (int step = 0; step < 8; step++) {
    await finger.moveBy(travel / 8);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await finger.up();
  await tester.pumpAndSettle();
}

Future<void> _pumpSwipe(
  WidgetTester tester, {
  required List<String> selected,
  List<String>? held,
  VoidCallback? onTap,
  bool isZoomed = false,
  bool atLastItem = false,
  List<double>? dragged,
  List<String>? dismissed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ShelfSwipe(
          isZoomed: isZoomed,
          onPrevious: () => selected.add('previous'),
          onNext: atLastItem ? null : () => selected.add('next'),
          onHold: held == null ? null : () => held.add('held'),
          onDragDown: dragged?.add,
          onDismiss: dismissed == null ? null : () => dismissed.add('dismiss'),
          // The viewport's tap, standing in for the real one: fullscreen wires
          // a chrome toggle here, and it is what the hold has to take away.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: const SizedBox.expand(
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    ),
  );
}
