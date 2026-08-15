import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/backdrop_drift_scope.dart';
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
Future<void> _pump(WidgetTester tester, {double systemBar = 0}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 800),
          viewPadding: EdgeInsets.only(bottom: systemBar),
          padding: EdgeInsets.only(bottom: systemBar),
        ),
        child: const Scaffold(
          body: DetailEditorialBody(
            preview: ColoredBox(key: _preview, color: Colors.black),
            metadata: SizedBox(key: _metadata, height: 900),
            applyButton: SizedBox(key: _apply, height: 84),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('runs the wallpaper to every edge, the apply button included', (
    WidgetTester tester,
  ) async {
    // The point of the layout: the image is the page, not a picture in a box
    // above a panel. **The bottom edge is the part the owner had to ask for
    // twice** — "make the fullscreen so that i can see the full background"
    // (2026-08-15). It used to stop where the apply button began, which cost
    // the picture the button's height at every sheet size; the button and the
    // sheet ride over it now. The image is `BoxFit.contain`, so the box it is
    // fitted to is the whole feature, not the pixels behind an opaque pill.
    await _pump(tester);

    final Rect image = tester.getRect(find.byKey(_preview));
    final Rect body = tester.getRect(find.byType(DetailEditorialBody));
    expect(image.left, body.left);
    expect(image.right, body.right);
    expect(image.top, body.top);
    expect(image.bottom, body.bottom);
  });

  testWidgets('does not clip the apply button off the bottom', (
    WidgetTester tester,
  ) async {
    // It was absolutely positioned first, which looked equivalent and was not:
    // its own SafeArea had nothing to inset against inside a Positioned, so on
    // the device it ran under the system bar with its label and icon cut off.
    await _pump(tester);

    final Rect apply = tester.getRect(find.byKey(_apply));
    final Rect body = tester.getRect(find.byType(DetailEditorialBody));
    expect(apply.bottom, lessThanOrEqualTo(body.bottom));
    expect(apply.height, 84);
  });

  testWidgets('lifts the apply button clear of the system bar', (
    WidgetTester tester,
  ) async {
    // The device found this one. The button's own SafeArea reports nothing
    // under a Scaffold with `extendBodyBehindAppBar`, so it was drawn half
    // under the system bar with its label cut off — while the same widget in
    // the wide layout rendered fine.
    const double systemBar = 48;
    await _pump(tester, systemBar: systemBar);

    final Rect apply = tester.getRect(find.byKey(_apply));
    final Rect body = tester.getRect(find.byType(DetailEditorialBody));
    expect(body.bottom - apply.bottom, systemBar);
  });

  testWidgets('opens with the wallpaper unobstructed', (
    WidgetTester tester,
  ) async {
    // The owner's finding, in their words: "the image is behind the details and
    // i cant hide it". The subject of this screen is the picture, so it arrives
    // whole and the facts are asked for.
    await _pump(tester);

    // Asserted in dip, because the peek is a height: it is exactly the grip
    // plus the heading, so the sheet's bottom edge never slices a fact row in
    // half. "the details when minimized its clipping", as the owner put it
    // (2026-08-15) — a fraction cannot know where the heading ends.
    final Rect apply = tester.getRect(find.byKey(_apply));
    final double sheetTop = tester
        .getTopLeft(find.byKey(DetailEditorialBody.sheetKey))
        .dy;

    expect(
      apply.top - sheetTop,
      closeTo(DetailEditorialBody.peekSheetHeight, 1),
      reason: 'the wallpaper must arrive whole, not two fifths behind a panel',
    );
  });

  testWidgets('bumps the wallpaper up instead of covering it', (
    WidgetTester tester,
  ) async {
    // The other half of the owner's ask: raising the facts must move the
    // picture out of their way. Half the sheet's own travel, so the preview's
    // bottom edge stays under the sheet rather than opening a gap of dead
    // canvas beneath it.
    await _pump(tester);
    final double before = tester.getRect(find.byKey(_preview)).center.dy;

    await _raiseSheet(tester);

    final Rect after = tester.getRect(find.byKey(_preview));
    final double sheetTop = tester
        .getTopLeft(find.byKey(DetailEditorialBody.sheetKey))
        .dy;
    expect(after.center.dy, lessThan(before));
    expect(
      after.bottom,
      greaterThan(sheetTop),
      reason: 'a full-rate lift would strand dead canvas above the sheet',
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

  testWidgets('drifts the wallpaper behind the sheet as it rises', (
    WidgetTester tester,
  ) async {
    // The parallax the browse wall could not have: a shelf may crop nothing,
    // and the letterbox scenery behind this preview is cropped already.
    await _pump(tester);
    expect(_drift(tester), 0);

    await _raiseSheet(tester);

    // Up, with the sheet — the backdrop must travel the same way as the thing
    // in front of it, only less, or it reads as sliding rather than as depth.
    expect(_drift(tester), lessThan(0));
    expect(_drift(tester), greaterThanOrEqualTo(-1));
  });

  testWidgets('spends the whole drift by the time the sheet is up', (
    WidgetTester tester,
  ) async {
    // Mapped across the sheet's own travel, not an arbitrary distance, so the
    // scenery arrives exactly as the sheet does.
    await _pump(tester);

    await _raiseSheet(tester);

    expect(_drift(tester), closeTo(-1, 0.001));
  });

  testWidgets('brings the wallpaper back as the sheet is put down', (
    WidgetTester tester,
  ) async {
    // The round trip. Raised, the scenery has drifted up; put back down it
    // must not stay there — a drift that only ever accumulates would leave the
    // backdrop permanently off-centre after a few drags.
    await _pump(tester);
    await _raiseSheet(tester);
    expect(_drift(tester), lessThan(0));

    final Finder sheet = find.byKey(DetailEditorialBody.sheetKey);
    await tester.dragFrom(
      Offset(tester.getCenter(sheet).dx, tester.getTopLeft(sheet).dy + 24),
      const Offset(0, 900),
    );
    await tester.pumpAndSettle();

    expect(_drift(tester), closeTo(0, 0.001));
  });

  testWidgets('gets out of the way when pushed down', (
    WidgetTester tester,
  ) async {
    // The device found this: with the sheet's floor at its resting size there
    // was no gesture that uncovered the picture, so a phone showed every
    // wallpaper with its bottom two fifths behind a panel — the image read as
    // opening minimised on the one screen whose subject is the image.
    await _pump(tester);
    final Finder sheet = find.byKey(DetailEditorialBody.sheetKey);
    await _raiseSheet(tester);
    final double raised = tester.getTopLeft(sheet).dy;

    await tester.dragFrom(
      Offset(tester.getCenter(sheet).dx, raised + 24),
      const Offset(0, 900),
    );
    await tester.pumpAndSettle();

    final Rect body = tester.getRect(find.byType(DetailEditorialBody));
    final double pushedDown = tester.getTopLeft(sheet).dy;
    expect(pushedDown, greaterThan(raised));
    // A peek, not a dismissal: the grip stays on screen, or the sheet becomes
    // a feature the user has to rediscover.
    expect(pushedDown, lessThan(body.bottom));
    expect(find.byKey(DetailEditorialBody.sheetKey), findsOneWidget);
  });

  testWidgets('has not moved anything at the moment the screen opens', (
    WidgetTester tester,
  ) async {
    // Both effects are measured from the peek, so a screen the user has not
    // touched yet is showing the wallpaper exactly as the shelf handed it over.
    await _pump(tester);

    expect(_drift(tester), 0);
  });

  testWidgets('comes to rest at a size, never where the finger left it', (
    WidgetTester tester,
  ) async {
    // Snapped. A sheet abandoned at 31% is what reads as a stuck scroll rather
    // than as a sheet — the question the device pass was owed.
    await _pump(tester);
    final Finder sheet = find.byKey(DetailEditorialBody.sheetKey);
    final double resting = tester.getTopLeft(sheet).dy;

    await tester.dragFrom(
      Offset(tester.getCenter(sheet).dx, resting + 24),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    // Measured against the sheet's own scrollable area, not the body: the
    // apply button sits below it, so the fractions are of a shorter box.
    final Rect area = tester.getRect(find.byType(DraggableScrollableSheet));
    final double settled =
        (area.bottom - tester.getTopLeft(sheet).dy) / area.height;
    expect(
      <double>[
        DetailEditorialBody.peekFractionIn(area.height),
        DetailEditorialBody.restingSheetFraction,
        DetailEditorialBody.fullSheetFraction,
      ].map((double size) => (settled - size).abs()).reduce(min),
      lessThan(0.03),
    );
  });

  test('the top wash still covers the controls, not just the edge', () {
    // The device found this against a genuinely pale wallpaper: the white bar
    // controls measured 2.9:1, over the 3:1 floor for UI graphics by nothing.
    // A straight ramp spends its darkness above the controls where there is
    // nothing to read, so the wash holds full strength down past them instead.
    expect(
      DetailEditorialBody.topScrimAlphaAt(0),
      DetailEditorialBody.topScrimOpacity,
    );
    expect(
      DetailEditorialBody.topScrimAlphaAt(
        DetailEditorialBody.topScrimControlRow,
      ),
      DetailEditorialBody.topScrimOpacity,
      reason: 'the controls sit here; a fading wash is what failed on device',
    );
    // And it is a wash, not a bar: gone by its own height, so nothing draws an
    // edge across the wallpaper.
    expect(
      DetailEditorialBody.topScrimAlphaAt(DetailEditorialBody.topScrimHeight),
      0,
    );
    expect(
      DetailEditorialBody.topScrimAlphaAt(
        (DetailEditorialBody.topScrimControlRow +
                DetailEditorialBody.topScrimHeight) /
            2,
      ),
      closeTo(DetailEditorialBody.topScrimOpacity / 2, 0.001),
    );
  });

  testWidgets('paints that wash, held and then faded', (
    WidgetTester tester,
  ) async {
    // The constant is only worth pinning if the gradient is actually built from
    // it — three stops, the first two at the same opacity.
    await _pump(tester);

    final DecoratedBox scrim = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(DetailEditorialBody),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final LinearGradient wash =
        (scrim.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(
      wash.colors.first.a,
      closeTo(DetailEditorialBody.topScrimOpacity, 0.01),
    );
    expect(wash.colors[1].a, wash.colors.first.a);
    expect(wash.colors.last.a, 0);
  });
}

/// How far the scenery has been told to drift, from the scope over the body.
double _drift(WidgetTester tester) {
  return tester
      .widget<BackdropDriftScope>(find.byType(BackdropDriftScope))
      .drift
      .value;
}

/// Drags the sheet to the top of its travel.
///
/// From the sheet's own surface: the metadata inside it is taller than the
/// screen, so its centre — where `drag` aims — is off-screen.
Future<void> _raiseSheet(WidgetTester tester) async {
  final Finder sheet = find.byKey(DetailEditorialBody.sheetKey);
  await tester.dragFrom(
    Offset(tester.getCenter(sheet).dx, tester.getTopLeft(sheet).dy + 24),
    const Offset(0, -600),
  );
  await tester.pumpAndSettle();
}
