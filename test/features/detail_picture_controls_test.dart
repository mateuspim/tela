import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/features/detail/detail_picture_controls.dart';
import 'package:tela/features/detail/detail_sheet_progress.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ValueNotifier<double> lift,
  required ValueNotifier<double> risen,
  required VoidCallback onFullscreen,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DetailSheetProgress(
          lift: lift,
          risen: risen,
          child: DetailPictureControls(
            onFullscreen: onFullscreen,
            onPrevious: () {},
            onNext: () {},
          ),
        ),
      ),
    ),
  );
}

/// Whether the controls' own outermost semantics gate is closed — the first
/// ExcludeSemantics under them, ahead of the ones tooltips carry inside.
bool _excluded(WidgetTester tester) => tester
    .widget<ExcludeSemantics>(
      find
          .descendant(
            of: find.byType(DetailPictureControls),
            matching: find.byType(ExcludeSemantics),
          )
          .first,
    )
    .excluding;

void main() {
  group('DetailPictureControls', () {
    test('stay fully shown to the middle stop, then fade out by full', () {
      expect(DetailPictureControls.shownAt(0), 1);
      expect(DetailPictureControls.shownAt(0.45), 1);
      expect(DetailPictureControls.shownAt(0.75), closeTo(0.5, 1e-9));
      expect(DetailPictureControls.shownAt(1), 0);
    });

    testWidgets('fullscreen stays pinned while the picture is bumped up', (
      WidgetTester tester,
    ) async {
      // Riding the bump, the button left the screen at the middle stop
      // (device survey, SM-X730, 2026-10-05).
      final ValueNotifier<double> lift = ValueNotifier<double>(0);
      final ValueNotifier<double> risen = ValueNotifier<double>(0);
      await _pump(tester, lift: lift, risen: risen, onFullscreen: () {});
      final Finder button = find.byIcon(Icons.fullscreen);
      final double restingTop = tester.getTopLeft(button).dy;
      final double height = tester
          .getSize(
            find.byType(DetailPictureControls),
          )
          .height;

      lift.value = 0.2;
      await tester.pump();

      expect(tester.getTopLeft(button).dy, restingTop + 0.2 * height);
    });

    testWidgets('a raised sheet hides them from taps and screen readers', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      final ValueNotifier<double> risen = ValueNotifier<double>(0);
      await _pump(
        tester,
        lift: ValueNotifier<double>(0),
        risen: risen,
        onFullscreen: () => taps++,
      );

      expect(_excluded(tester), isFalse);
      risen.value = 1;
      await tester.pump();
      await tester.tap(find.byIcon(Icons.fullscreen), warnIfMissed: false);

      expect(taps, 0);
      expect(_excluded(tester), isTrue);
    });
  });
}
