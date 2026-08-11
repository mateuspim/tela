import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/shelf_swipe.dart';

/// Pins the rules the fullscreen viewer had carried inline since slice 3, now
/// that Detail's pager depends on the same widget for all of its paging.
///
/// The one that is not obvious is the two-finger case: a pinch drifts, and if
/// that drift were read as a swipe the page would turn out from under a zoom
/// the user was still setting up.
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
}

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
  bool isZoomed = false,
  bool atLastItem = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ShelfSwipe(
          isZoomed: isZoomed,
          onPrevious: () => selected.add('previous'),
          onNext: atLastItem ? null : () => selected.add('next'),
          child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
        ),
      ),
    ),
  );
}
