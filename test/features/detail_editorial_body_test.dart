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
Future<void> _pump(
  WidgetTester tester, {
  double systemBar = 0,
  DraggableScrollableController? sheetController,
}) async {
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
        child: Scaffold(
          body: DetailEditorialBody(
            preview: const ColoredBox(key: _preview, color: Colors.black),
            metadata: const SizedBox(key: _metadata, height: 900),
            applyButton: const SizedBox(key: _apply, height: 84),
            sheetController: sheetController,
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

    // Asserted in dip, because the peek is a height: it is exactly the grip,
    // and the grip is the whole of what a closed sheet shows. "the details
    // when minimized its clipping", then "make the handle invisible" — the
    // owner, 2026-08-15. A fraction could not have landed on either.
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

    // Dragged from the handle, for the reason _raiseSheet spells out: the
    // peek is 20dp tall, so a grab further down lands past the sheet entirely.
    await tester.dragFrom(
      Offset(tester.getCenter(sheet).dx, before + 10),
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

  testWidgets('shows no surface at all until the sheet is pulled', (
    WidgetTester tester,
  ) async {
    // "make like a the handle invisible and when we are opening it up it start
    // to have background color fading it in" (the owner, 2026-08-15). The
    // closed sheet used to be an opaque band across the foot of the picture,
    // which is information about the wallpaper that the wallpaper screen was
    // hiding.
    await _pump(tester);

    expect(_surfaceAlpha(tester), 0);

    await _raiseSheet(tester);

    // Solid by the time it comes to rest anywhere: the fade is what the sheet
    // looks like while it is moving, never what it settles as.
    expect(_surfaceAlpha(tester), 1);
  });

  testWidgets('the apply button rides on the same surface as the sheet', (
    WidgetTester tester,
  ) async {
    // "the set wallpaper and details one was glued they seem disconnected" —
    // the owner, looking at the strip of wallpaper that ran between the two.
    // One colour, at one opacity, on two boxes that abut.
    await _pump(tester);
    await _raiseSheet(tester);

    final Rect sheet = tester.getRect(
      find.byKey(DetailEditorialBody.sheetKey),
    );
    // The closest ColoredBox above the button is the one `_glued` paints;
    // further out are the Scaffold's own.
    final Finder glue = find
        .ancestor(of: find.byKey(_apply), matching: find.byType(ColoredBox))
        .first;

    expect(tester.widget<ColoredBox>(glue).color, _sheetColor(tester));
    expect(tester.getRect(glue).top, closeTo(sheet.bottom, 0.5));
  });

  testWidgets(
    'the handle is outlined and shadowed while alone on the picture',
    (
      WidgetTester tester,
    ) async {
      // The device found this twice: a plain white handle over no surface is
      // invisible on a near-white wallpaper, and a shadow alone then measured
      // 1.51:1 against a pure-white one — a halo is not an edge (SM-X730,
      // 2026-08-15). Both are what the missing surface owes it, so both are
      // strongest at the peek and gone once the panel is solid and the scheme's
      // own contrast has taken over.
      await _pump(tester);
      expect(_gripOutline(tester).a, greaterThan(0.3));
      expect(_gripShadow(tester).a, greaterThan(0.3));

      await _raiseSheet(tester);

      expect(_gripOutline(tester).a, 0);
      expect(_gripShadow(tester).a, 0);
    },
  );

  testWidgets('the closed sheet is a whole touch target, not a hairline', (
    WidgetTester tester,
  ) async {
    // "the details button is kinda hit or miss on portrait" (the owner,
    // 2026-08-24). The peek *is* the grip, so the grip's band was the entire
    // hit area of the only control that opens the facts — 21dp of it, with the
    // apply button glued below and a tap-to-fullscreen picture above, so both
    // misses did something loud. Flutter gives its own drag handle
    // `kMinInteractiveDimension`; this one draws itself and had to be told.
    await _pump(tester);

    expect(
      tester.getSize(_gripBand()).height,
      kMinInteractiveDimension,
      reason: 'a thumb is owed 48dp, and this band is the whole of the peek',
    );
    expect(
      tester.getRect(find.byKey(DetailEditorialBody.sheetKey)).height,
      greaterThanOrEqualTo(kMinInteractiveDimension),
    );
  });

  testWidgets('gives the band back once the panel is solid', (
    WidgetTester tester,
  ) async {
    // The reach is a closed-sheet problem. Open, the handle is decoration —
    // and 48dp of blank above the first fact row is exactly the kind of thing
    // the peek's own history says gets noticed on a device.
    await _pump(tester);

    await _raiseSheet(tester);

    expect(
      tester.getSize(_gripBand()).height,
      DetailEditorialBody.sheetGripSettledHeight,
    );
  });

  testWidgets('tapping the handle opens the sheet, and again closes it', (
    WidgetTester tester,
  ) async {
    // The labelled equivalent of the upward throw on the picture: a gesture is
    // invisible to a screen reader, so the sheet is never reachable only that
    // way. A tap is also simply the cheaper thing to do to a handle.
    final DraggableScrollableController sheet = DraggableScrollableController();
    addTearDown(sheet.dispose);
    await _pump(tester, sheetController: sheet);
    final Finder surface = find.byKey(DetailEditorialBody.sheetKey);
    final double closed = tester.getTopLeft(surface).dy;

    await tester.tap(_gripBand());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(surface).dy, lessThan(closed));

    await tester.tap(_gripBand());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(surface).dy, closeTo(closed, 1));
  });

  testWidgets('revealing a sheet already open never lowers it', (
    WidgetTester tester,
  ) async {
    // The throw that calls this is armed across the whole picture, and a
    // picture is still visible above a fully-raised sheet. Without the guard a
    // flick up there would pull the facts *down*, which is the opposite of
    // what the gesture says.
    final DraggableScrollableController sheet = DraggableScrollableController();
    addTearDown(sheet.dispose);
    await _pump(tester, sheetController: sheet);
    await _raiseSheet(tester);
    final double open = sheet.size;

    await DetailEditorialBody.revealSheet(sheet, animate: false);
    await tester.pumpAndSettle();

    expect(sheet.size, open);
    expect(open, greaterThan(DetailEditorialBody.restingSheetFraction));
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

  test('the top wash holds over the status bar, not just the edge', () {
    // The device found this against a genuinely pale wallpaper: white chrome
    // measured 2.9:1, over the 3:1 floor for UI graphics by nothing. A
    // straight ramp spends its darkness above what there is to read, so the
    // wash holds full strength down past it instead. Since the bar's controls
    // moved into PhotoCapsules (2026-10-05) what it holds over is the status
    // bar's clock alone.
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

/// The band around the handle — what a thumb actually has to hit, as opposed
/// to the 32x5 bar drawn in the middle of it.
///
/// Found by type rather than by a key, for the same reason [_gripDecoration]
/// is: the grip is private to the body. `Scrollable` builds a
/// `RawGestureDetector`, not this type, so the sheet's own scrolling does not
/// answer here.
Finder _gripBand() => find
    .descendant(
      of: find.byKey(DetailEditorialBody.sheetKey),
      matching: find.byType(GestureDetector),
    )
    .first;

/// How far the scenery has been told to drift, from the scope over the body.
double _drift(WidgetTester tester) {
  return tester
      .widget<BackdropDriftScope>(find.byType(BackdropDriftScope))
      .drift
      .value;
}

/// The handle's decoration. Found as the first `Container` inside the sheet
/// rather than by a key: the grip is private to the body, and a key exported
/// only for a test would outlive the reason it was added.
BoxDecoration _gripDecoration(WidgetTester tester) {
  final Container grip = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(DetailEditorialBody.sheetKey),
          matching: find.byType(Container),
        )
        .first,
  );
  return grip.decoration! as BoxDecoration;
}

/// The handle's shadow colour, whose alpha is the whole of the assertion.
Color _gripShadow(WidgetTester tester) =>
    _gripDecoration(tester).boxShadow!.single.color;

/// The handle's outline colour, likewise.
Color _gripOutline(WidgetTester tester) =>
    _gripDecoration(tester).border!.top.color;

/// The colour the sheet is actually painting, alpha included.
Color _sheetColor(WidgetTester tester) {
  final DecoratedBox sheet = tester.widget<DecoratedBox>(
    find.byKey(DetailEditorialBody.sheetKey),
  );
  return (sheet.decoration as BoxDecoration).color!;
}

/// How solid that surface is, 0..1.
double _surfaceAlpha(WidgetTester tester) => _sheetColor(tester).a;

/// Drags the sheet to the top of its travel, starting on its handle.
///
/// From the sheet's own surface rather than its centre: the metadata inside it
/// is taller than the screen, so the centre `drag` aims at is off-screen.
///
/// The offset must stay inside [DetailEditorialBody.peekSheetHeight] — since
/// the peek became the handle alone it is only 20dp tall, and a grab 24dp down
/// landed *past* the sheet, on the button block below it. `DraggableScrollable
/// Sheet` is moved by the scrollable it owns and by nothing else, so that drag
/// silently did nothing and four tests failed reporting a drift of zero.
Future<void> _raiseSheet(WidgetTester tester) async {
  final Finder sheet = find.byKey(DetailEditorialBody.sheetKey);
  await tester.dragFrom(
    Offset(tester.getCenter(sheet).dx, tester.getTopLeft(sheet).dy + 10),
    const Offset(0, -600),
  );
  await tester.pumpAndSettle();
}
