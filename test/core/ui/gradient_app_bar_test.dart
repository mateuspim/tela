import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/floating_capsule.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';

/// Finds the gradient painted behind a [GradientAppBar]'s contents.
Gradient _bandGradient(WidgetTester tester) {
  final Iterable<DecoratedBox> boxes = tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  );
  final BoxDecoration decoration = boxes
      .map((DecoratedBox box) => box.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((BoxDecoration d) => d.gradient != null);
  return decoration.gradient!;
}

void main() {
  group('GradientAppBar', () {
    testWidgets('the bar paints nothing, so the wash shows', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: GradientAppBar(title: const Text('Browse'))),
        ),
      );

      final AppBar bar = tester.widget<GradientAppBar>(
        find.byType(GradientAppBar),
      );
      expect(bar.backgroundColor, Colors.transparent);
      expect(bar.elevation, 0);
    });

    testWidgets('a pushed screen floats its back button in a capsule', (
      WidgetTester tester,
    ) async {
      final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: nav, home: const SizedBox()),
      );
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => Scaffold(
              appBar: GradientAppBar.pushed(title: const Text('Tag')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(FloatingCapsule),
          matching: find.byType(BackButton),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Tag'), findsNothing);
    });

    testWidgets('the wash fills the whole bar, not zero pixels of it', (
      WidgetTester tester,
    ) async {
      // A childless DecoratedBox in AppBar's passthrough stack sized itself to
      // the loose constraints' minimum — zero height — so the band was in the
      // tree, passed the colour tests, and never painted (SM-X730, 2026-10-05).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: GradientAppBar(title: const Text('Browse'))),
        ),
      );

      final Finder band = find.byWidgetPredicate(
        (Widget w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient != null,
      );
      expect(
        tester.getSize(band),
        tester.getSize(find.byType(GradientAppBar)),
      );
    });

    testWidgets('the wash is fully opaque, so no wall shows through', (
      WidgetTester tester,
    ) async {
      // The whole reason this replaced the frosted bar: over a grid of
      // thumbnails a see-through bar reads as broken. Every gradient stop must
      // be opaque — drop it below 1 and wallpapers bleed through the chrome.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: GradientAppBar(title: const Text('Browse'))),
        ),
      );

      final Gradient gradient = _bandGradient(tester);
      for (final Color color in gradient.colors) {
        expect(color.a, 1.0, reason: 'a see-through stop leaks the wall');
      }
    });
  });
}
