import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/tile_entrance.dart';

const Key _tile = Key('entering-tile');

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.ancestor(
        of: find.byKey(_tile),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

Future<void> _pump(
  WidgetTester tester, {
  required bool animate,
  Duration delay = Duration.zero,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: TileEntrance(
        animate: animate,
        delay: delay,
        child: const SizedBox(key: _tile, width: 100, height: 100),
      ),
    ),
  );
}

void main() {
  testWidgets('arrives rather than appearing', (WidgetTester tester) async {
    await _pump(tester, animate: true);

    expect(_opacity(tester), 0);

    // `pumpAndSettle`, not `pump(duration)`: a single advance fires the delay
    // timer and starts the ticker in the same frame, so the animation reads
    // elapsed-zero and the tile is still invisible. Every settled assertion
    // here has that shape.
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('waits out its delay before starting', (
    WidgetTester tester,
  ) async {
    // The delay is what makes a row cascade instead of flashing as one block.
    await _pump(
      tester,
      animate: true,
      delay: const Duration(milliseconds: 200),
    );

    await tester.pump(const Duration(milliseconds: 150));
    expect(_opacity(tester), 0, reason: 'still waiting out the delay');

    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('draws in place when it is not to animate', (
    WidgetTester tester,
  ) async {
    // Both a recycled tile and a reduce-motion device take this path, and
    // neither may spend a frame invisible.
    await _pump(tester, animate: false, delay: const Duration(seconds: 1));

    expect(_opacity(tester), 1);
  });

  testWidgets('survives being disposed mid-delay', (
    WidgetTester tester,
  ) async {
    // The routine case, not the corner: a fast scroll disposes a row before
    // its cascade has reached the far end of it. An unguarded timer would
    // touch a dead State and fail the test with a framework exception.
    await _pump(tester, animate: true, delay: const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });
}
