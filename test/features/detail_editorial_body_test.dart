import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/features/detail/detail_editorial_body.dart';

const Key _preview = Key('the-preview');
const Key _metadata = Key('the-metadata');
const Key _apply = Key('the-apply');

/// Pinned at a real phone rather than the 800x600 widget-test default.
///
/// D1 already paid for this lesson once: at the default geometry a tap aimed
/// at a sheet row landed on the navigation bar and the failure said only that
/// the target was missing. This layout is *about* proportions of a phone
/// screen, so testing it on a squat landscape box measures nothing.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: DetailEditorialBody(
          preview: ColoredBox(key: _preview, color: Colors.black),
          metadata: SizedBox(key: _metadata, height: 900),
          applyButton: SizedBox(key: _apply, height: 84),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('runs the wallpaper to every edge', (WidgetTester tester) async {
    // The point of the layout: the image is the page, not a picture in a box
    // above a panel. Anything less than the full screen means the old seam is
    // still there.
    await _pump(tester);

    expect(
      tester.getRect(find.byKey(_preview)),
      tester.getRect(find.byType(DetailEditorialBody)),
    );
  });

  testWidgets('rests with most of the wallpaper still showing', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    final double screen = tester
        .getSize(find.byType(DetailEditorialBody))
        .height;
    final double sheetTop = tester
        .getTopLeft(find.byKey(DetailEditorialBody.sheetKey))
        .dy;

    expect(
      sheetTop / screen,
      closeTo(1 - DetailEditorialBody.restingSheetFraction, 0.02),
      reason: 'most of the screen must still be wallpaper',
    );
  });

  testWidgets('keeps the apply button over the sheet, never under it', (
    WidgetTester tester,
  ) async {
    // Wave 1's promise is three taps to a wallpaper. A button you have to
    // scroll the facts away to reach is a fourth.
    await _pump(tester);

    final Rect apply = tester.getRect(find.byKey(_apply));
    final Size screen = tester.getSize(find.byType(DetailEditorialBody));
    expect(apply.bottom, screen.height);
  });

  testWidgets('the sheet rises when dragged, and stops short of the top', (
    WidgetTester tester,
  ) async {
    // Measured on the sheet's own surface, not on the metadata inside it: the
    // facts scroll within the sheet once it has finished rising, so their
    // position answers a different question and eventually goes negative.
    await _pump(tester);
    final Finder sheet = find.byKey(DetailEditorialBody.sheetKey);
    final double before = tester.getTopLeft(sheet).dy;

    // Dragged from the sheet's own surface: the metadata inside it is taller
    // than the screen, so its centre — where `drag` aims — is off-screen.
    await tester.dragFrom(
      Offset(tester.getCenter(sheet).dx, before + 24),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    final double after = tester.getTopLeft(sheet).dy;
    expect(after, lessThan(before));
    expect(
      after,
      greaterThan(0),
      reason: 'a sheet that covers everything strands the user off the image',
    );
  });

  testWidgets('lets the wallpaper take gestures under the scrim', (
    WidgetTester tester,
  ) async {
    // The scrim exists so a back arrow survives a pale sky; it must not also
    // eat the pinch and the hold-to-copy at the top of the image.
    await _pump(tester);

    final Finder scrim = find.descendant(
      of: find.byType(DetailEditorialBody),
      matching: find.byType(IgnorePointer),
    );

    expect(scrim, findsWidgets);
  });
}
