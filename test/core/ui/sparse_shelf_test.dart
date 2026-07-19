import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';

/// D2a — a shelf holding one or two wallpapers draws them large.
///
/// The packer's own ceiling is `targetRowHeight`, a measurement about a *full*
/// wall, so a library of one came out the size of a tile among hundreds: 93dip
/// on a 753dip tablet viewport, adrift above a screen and a half of black
/// (device, 2026-07-19). The pure rule is pinned in `justified_rows_test.dart`;
/// what is pinned here is the wiring — that the shelf measures its own viewport
/// and hands that down.
void main() {
  testWidgets('a lone wallpaper is drawn against the viewport, not the wall', (
    WidgetTester tester,
  ) async {
    await _pumpShelf(tester, ratios: <double>[1080 / 2400], height: 750);

    // Two thirds of the viewport. The measurement is taken outside the
    // shelf's own padding, so the padding does not come off it.
    expect(_tileHeight(tester), closeTo(500, 1));
  });

  testWidgets('the same wallpaper on a taller viewport is drawn taller', (
    WidgetTester tester,
  ) async {
    // The claim that it is the *viewport* being measured and not a constant:
    // the wallpaper, the width and the density are identical across the two.
    await _pumpShelf(tester, ratios: <double>[1080 / 2400], height: 750);
    final double shortViewport = _tileHeight(tester);

    await _pumpShelf(tester, ratios: <double>[1080 / 2400], height: 1200);

    expect(_tileHeight(tester), greaterThan(shortViewport));
  });

  testWidgets('a full shelf keeps its rhythm', (WidgetTester tester) async {
    // The ceiling reaches only a shelf that never closed a row. A wall of
    // wallpapers must not have its rows blown up to two thirds of the screen.
    await _pumpShelf(
      tester,
      ratios: List<double>.filled(24, 16 / 9),
      height: 750,
    );

    expect(_tileHeight(tester), lessThan(300));
  });
}

double _tileHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey<int>(0))).height;

Future<void> _pumpShelf(
  WidgetTester tester, {
  required List<double> ratios,
  required double height,
}) async {
  // The view, not a SizedBox: the test surface defaults to 800x600 and clamps
  // any box taller than that, so a shelf "750 tall" silently measured 600 and
  // the ceiling came out two thirds of the wrong number.
  tester.view.physicalSize = Size(1200, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: JustifiedWallpaperGrid(
            itemCount: ratios.length,
            aspectRatioOf: (int index) => ratios[index],
            itemBuilder:
                (BuildContext context, int index, double _, double _) =>
                    ColoredBox(
                      key: ValueKey<int>(index),
                      color: const Color(0xFF000000),
                    ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
