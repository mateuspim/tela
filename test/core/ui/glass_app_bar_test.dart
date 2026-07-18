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

    test('a bottom widget counts toward the height a GlassBody must clear', () {
      final GlassAppBar plain = GlassAppBar(title: const Text('x'));
      final GlassAppBar withTabs = GlassAppBar(
        title: const Text('x'),
        bottom: const TabBar(tabs: <Widget>[Tab(text: 'a'), Tab(text: 'b')]),
      );

      expect(
        withTabs.preferredSize.height,
        greaterThan(plain.preferredSize.height),
      );
    });
  });

  group('GlassBody', () {
    testWidgets('adds the bar height onto the top inset its child sees', (
      WidgetTester tester,
    ) async {
      late double topInset;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: GlassBody(
            barHeight: 100,
            child: Builder(
              builder: (BuildContext context) {
                topInset = MediaQuery.paddingOf(context).top;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // The status bar (24) plus the frosted bar (100): the first row clears it.
      expect(topInset, 124);
    });
  });
}
