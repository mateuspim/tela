import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';

Key _tileKey(int index) => ValueKey<String>('tile-$index');

/// The opacity the tile at [index] is currently drawn at, or null when that
/// tile is not built — a shelf recycles, so "off screen" is a real answer.
double? _opacityOf(WidgetTester tester, int index) {
  final Finder tile = find.byKey(_tileKey(index));
  if (tile.evaluate().isEmpty) return null;
  return tester
      .widget<FadeTransition>(
        find.ancestor(of: tile, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;
}

Future<ScrollController> _pumpWall(
  WidgetTester tester, {
  bool disableAnimations = false,
  int itemCount = 90,
}) async {
  final ScrollController controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: JustifiedWallpaperGrid(
          itemCount: itemCount,
          controller: controller,
          // Landscape, so rows close at several tiles each and scrolling
          // genuinely recycles them.
          aspectRatioOf: (int index) => 1.5,
          itemBuilder: (BuildContext context, int index, double w, double h) =>
              SizedBox(key: _tileKey(index)),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('a wallpaper arrives once and never again', (
    WidgetTester tester,
  ) async {
    // The load-bearing claim of the entrance. A shelf recycles its rows, so a
    // tile scrolled off and back is a new widget for an image already seen —
    // animating that is the wall flickering under a scroll rather than
    // assembling. Drop the `_seen` set and this fails on the very first pump
    // after scrolling back.
    final ScrollController controller = await _pumpWall(tester);
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 0), 1);

    controller.jumpTo(2000);
    await tester.pump();
    expect(
      _opacityOf(tester, 0),
      isNull,
      reason: 'the wall must actually recycle for this test to mean anything',
    );

    controller.jumpTo(0);
    await tester.pump();

    expect(_opacityOf(tester, 0), 1);
  });

  testWidgets('the first sighting does arrive', (WidgetTester tester) async {
    // The other half: without it, "never animates" would pass vacuously.
    await _pumpWall(tester);

    expect(_opacityOf(tester, 0), 0);

    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 0), 1);
  });

  testWidgets('a row cascades rather than arriving as one block', (
    WidgetTester tester,
  ) async {
    await _pumpWall(tester);

    // Stepped, not advanced in one go: a single large advance fires every
    // delay timer and starts every ticker on the same frame, which collapses
    // the cascade this is measuring. The first small pump starts tile 0; the
    // second leaves tile 2 still inside its own delay.
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 130));

    final double? first = _opacityOf(tester, 0);
    final double? later = _opacityOf(tester, 2);
    expect(first, isNotNull);
    expect(later, isNotNull);
    expect(later, lessThan(first!));
  });

  testWidgets('draws the whole wall in place under reduce motion', (
    WidgetTester tester,
  ) async {
    await _pumpWall(tester, disableAnimations: true);

    expect(_opacityOf(tester, 0), 1);
    expect(_opacityOf(tester, 2), 1);
  });
}
