import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/glass_app_bar.dart';

void main() {
  group('GlassAppBar', () {
    testWidgets('frosts its surface with a backdrop blur', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: GlassAppBar(title: const Text('Browse')),
            body: const SizedBox.expand(),
          ),
        ),
      );

      // The blur is the whole point: an opaque bar would have none.
      final BackdropFilter filter = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(filter.filter, isA<ImageFilter>());
    });

    testWidgets('paints nothing itself, so the frost behind it shows', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: GlassAppBar(title: const Text('Browse'))),
        ),
      );

      final AppBar bar = tester.widget<GlassAppBar>(find.byType(GlassAppBar));
      expect(bar.backgroundColor, Colors.transparent);
      expect(bar.elevation, 0);
    });

    testWidgets('under extendBodyBehindAppBar, the body inset clears the bar', (
      WidgetTester tester,
    ) async {
      // The layout contract the grids depend on: Scaffold folds the bar's
      // height into the body's top padding, so a grid reading that inset (via
      // wallpaperGridPadding) starts below the bar instead of under it. Break
      // this — drop extendBodyBehindAppBar, or read the inset from a context
      // above the body — and the first row hides beneath the frost.
      late double bodyTopInset;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: GlassAppBar(
              toolbarHeight: 72,
              title: const Text('Browse'),
            ),
            body: Builder(
              builder: (BuildContext context) {
                bodyTopInset = MediaQuery.paddingOf(context).top;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      expect(bodyTopInset, greaterThanOrEqualTo(72));
    });
  });
}
