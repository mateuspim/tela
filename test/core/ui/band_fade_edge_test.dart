import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/band_fade_edge.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';

void main() {
  group('BandFadeEdge', () {
    testWidgets('fades surface to clear over the wall top padding only', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: BandFadeEdge(child: SizedBox.expand())),
      );

      final Finder fade = find.descendant(
        of: find.byType(BandFadeEdge),
        matching: find.byType(DecoratedBox),
      );
      // As tall as the wall's own top padding, so a listing at rest is
      // untouched.
      expect(tester.getSize(fade).height, wallpaperGridSpacing);
      expect(tester.getTopLeft(fade).dy, 0);

      final LinearGradient gradient =
          (tester.widget<DecoratedBox>(fade).decoration as BoxDecoration)
                  .gradient!
              as LinearGradient;
      expect(gradient.colors.first.a, 1);
      expect(gradient.colors.last.a, 0);
    });

    testWidgets('lets taps through to the wall beneath', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BandFadeEdge(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
            ),
          ),
        ),
      );

      await tester.tapAt(const Offset(100, 4));

      expect(taps, 1);
    });
  });
}
