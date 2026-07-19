import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tela_mark.dart';

void main() {
  testWidgets('draws square, at the size it was given', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const TelaMark(size: 40));

    expect(tester.getSize(find.byType(TelaMark)), const Size(40, 40));
  });

  testWidgets('inks itself in the brand seed, not the user accent', (
    WidgetTester tester,
  ) async {
    // The identity claim, and the reason the mark exists as its own widget: a
    // user who picks a fixed accent repaints the chrome but never the mark.
    // The accent here is far from the seed, so a painter that read
    // ColorScheme.primary could not pass by coincidence.
    await _pump(tester, const TelaMark(), accent: const Color(0xFFE57373));

    expect(_inkOf(tester), TelaTheme.brandSeed);
  });

  testWidgets('honours an explicit colour, for a mark on an image', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const TelaMark(color: Color(0xFF123456)));

    expect(_inkOf(tester), const Color(0xFF123456));
  });

  testWidgets('is decorative unless it is named', (WidgetTester tester) async {
    // A mark beside the wordmark must not announce itself: the wordmark is
    // already "tela", and two nodes saying so is the duplicate D6 went looking
    // for on the icon-only viewer controls.
    await _pump(tester, const TelaMark());

    expect(
      find.descendant(
        of: find.byType(TelaMark),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('tela'), findsNothing);
  });

  testWidgets('takes a name where it stands alone', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const TelaMark(semanticLabel: 'tela'));

    expect(find.bySemanticsLabel('tela'), findsOneWidget);
  });

  test('paints four bands, each shortened where it passes under', () {
    const TelaMarkPainter painter = TelaMarkPainter(Color(0xFF000000));
    final List<RRect> bands = _bandsOf(painter);

    expect(bands, hasLength(4));
    // Every band is one full frame-side long minus the crossing it ducks, so
    // none of them spans the frame edge to edge. A band that did would mean an
    // interlace drawn by tone rather than by a cut — the thing the monochrome
    // themed icon cannot show. See docs/BRAND.md.
    const double side = TelaMark.frameExtent;
    for (final RRect band in bands) {
      expect(band.longestSide, lessThan(side));
      expect(band.shortestSide, TelaMark.bandWidth);
    }
  });

  test('fills the box it is given, without the icon-mask padding', () {
    // The design grid keeps a wide margin so a launcher mask has clearance,
    // and in a widget there is no mask. Honour that margin here and a caller
    // asking for 30 gets a mark inked at 14 — which is what the rail lockup
    // looked like on the tablet before this. So the painter maps the frame,
    // not the grid, onto its box.
    final List<RRect> bands = _bandsOf(
      const TelaMarkPainter(Color(0xFF000000)),
    );
    final Rect inked = bands
        .skip(1)
        .fold(
          bands.first.outerRect,
          (Rect acc, RRect b) => acc.expandToInclude(b.outerRect),
        );

    expect(inked.left, 0);
    expect(inked.top, 0);
    expect(inked.width, TelaMark.frameExtent);
    expect(inked.height, TelaMark.frameExtent);
  });

  test('the geometry matches the normative source', () {
    // assets/brand/tela_mark.svg, the two Android vector drawables and this
    // painter are four renderings of one shape, and only this assertion
    // notices when they stop agreeing. Change them together, and update
    // docs/BRAND.md, which records these same numbers.
    expect(TelaMark.gridExtent, 108);
    expect(TelaMark.frameStart, 29);
    expect(TelaMark.frameEnd, 79);
    expect(TelaMark.bandWidth, 12);
    expect(TelaMark.cutMargin, 2.75);
    expect(TelaMark.frameExtent, 50);
  });

  test('the frame fits the launcher circular mask, which is the tight one', () {
    // Not the 72dp safe square: a round mask is a circle of radius 36 about
    // the canvas centre, and a square inscribed in it has a half-extent of
    // only 36/sqrt(2) ~ 25.45. At the safe square's full size the band ends
    // are sliced off and the interlace stops reading — checked by rendering
    // under both a circle and a squircle. Grow the frame and this fails first.
    const double half = TelaMark.frameExtent / 2;
    const double centre = TelaMark.gridExtent / 2;

    expect(TelaMark.frameStart + half, centre, reason: 'must sit centred');
    expect(half * 1.41422, lessThan(36));
  });
}

/// The colour the widget actually handed its painter.
Color _inkOf(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(TelaMark),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter! as TelaMarkPainter).color;
}

/// Replays [painter] onto a recording canvas and collects the bands it drew,
/// so the geometry tests pin what is painted rather than what is declared.
///
/// Painted at [TelaMark.frameExtent] so one design unit is one pixel and the
/// numbers come back as `docs/BRAND.md` states them.
List<RRect> _bandsOf(TelaMarkPainter painter) {
  final _BandRecorder canvas = _BandRecorder();
  painter.paint(canvas, const Size.square(TelaMark.frameExtent));
  return canvas.bands;
}

/// A [Canvas] that remembers the rounded rectangles drawn on it and ignores
/// everything else.
class _BandRecorder implements Canvas {
  final List<RRect> bands = <RRect>[];

  @override
  void drawRRect(RRect rrect, Paint paint) => bands.add(rrect);

  @override
  void noSuchMethod(Invocation invocation) {}
}

Future<void> _pump(WidgetTester tester, Widget child, {Color? accent}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TelaTheme.light(null, accent: accent),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}
