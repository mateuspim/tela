import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/ui/floating_capsule.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) {
  final ThemeData theme = brightness == Brightness.dark
      ? TelaTheme.dark(null)
      : TelaTheme.light(null);
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: child)),
  );
}

ShapeDecoration _decoration(WidgetTester tester) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(FloatingCapsule),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as ShapeDecoration;
}

void main() {
  group('FloatingCapsule', () {
    testWidgets('the fill is opaque, so no wall shows through the chrome', (
      WidgetTester tester,
    ) async {
      // Pass A2 built frosted chrome and the owner rejected it on device: the
      // thumbnails showed through the search bar. A capsule floats by shape
      // and shadow, never by translucency.
      await tester.pumpWidget(_host(const FloatingCapsule(child: Text('x'))));

      expect(_decoration(tester).color!.a, 1.0);
    });

    test('capsuleFill stays opaque even on a see-through scheme', () {
      final ColorScheme glassy = ColorScheme.fromSeed(
        seedColor: TelaTheme.brandSeed,
      ).copyWith(surfaceContainerHigh: const Color(0x80202020));

      expect(FloatingCapsule.capsuleFill(glassy).a, 1.0);
    });

    for (final Brightness brightness in Brightness.values) {
      test('capsuleFill is brighter than the band in $brightness', () {
        // Above even surfaceContainerHighest, so above the band (whose top is
        // surfaceContainer plus a brand wash):
        // a capsule darker than that reads as a recessed outline, not as
        // floating — what surfaceContainerHigh looked like on device.
        final ColorScheme scheme = ColorScheme.fromSeed(
          seedColor: TelaTheme.brandSeed,
          brightness: brightness,
        );

        expect(
          FloatingCapsule.capsuleFill(scheme).computeLuminance(),
          greaterThan(scheme.surfaceContainerHighest.computeLuminance()),
        );
      });
    }

    testWidgets('is a stadium by default and a rounded panel with a radius', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const FloatingCapsule(child: Text('x'))));
      expect(_decoration(tester).shape, isA<StadiumBorder>());

      await tester.pumpWidget(
        _host(const FloatingCapsule(radius: 28, child: Text('x'))),
      );
      final RoundedRectangleBorder panel =
          _decoration(tester).shape as RoundedRectangleBorder;
      expect(panel.borderRadius, BorderRadius.circular(28));
    });

    testWidgets('casts a softer shadow in light mode than in dark', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const FloatingCapsule(child: Text('x'))));
      final double dark = _decoration(tester).shadows!.single.color.a;

      await tester.pumpWidget(
        _host(
          const FloatingCapsule(child: Text('x')),
          brightness: Brightness.light,
        ),
      );
      // MaterialApp tweens between themes; let the swap land.
      await tester.pumpAndSettle();
      final double light = _decoration(tester).shadows!.single.color.a;

      expect(light, lessThan(dark));
    });
  });

  testWidgets('CapsuleActionCluster lays its actions out in one capsule', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CapsuleActionCluster(
          children: <Widget>[Icon(Icons.checklist), Icon(Icons.tune)],
        ),
      ),
    );

    expect(find.byType(FloatingCapsule), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.checklist)).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.tune)).dx),
    );
  });

  testWidgets('CapsuleActionCluster collapses when every action hides', (
    WidgetTester tester,
  ) async {
    // The app bar stays up while selecting and SelectModeButton hides itself:
    // a screen whose only action is Select must not keep an empty pill.
    await tester.pumpWidget(
      _host(
        const CapsuleActionCluster(
          children: <Widget>[SizedBox.shrink(), SizedBox.shrink()],
        ),
      ),
    );

    expect(tester.getSize(find.byType(CapsuleActionCluster)), Size.zero);
    expect(
      tester.renderObject(find.byType(CapsuleActionCluster)),
      paintsNothing,
    );
  });

  testWidgets('CapsuleActionCluster comes back once an action shows again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const CapsuleActionCluster(children: <Widget>[SizedBox.shrink()])),
    );
    int taps = 0;
    await tester.pumpWidget(
      _host(
        CapsuleActionCluster(
          children: <Widget>[
            IconButton(icon: const Icon(Icons.tune), onPressed: () => taps++),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(CapsuleActionCluster)).width,
      greaterThan(CapsuleActionCluster.inset * 2),
    );
    await tester.tap(find.byIcon(Icons.tune));
    expect(taps, 1);
  });

  testWidgets('CapsuleTrack reserves exactly the height it draws', (
    WidgetTester tester,
  ) async {
    final DefaultTabController tabs = DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          bottom: const CapsuleTrack(
            child: TabBar(
              tabs: <Widget>[
                Tab(text: 'Latest'),
                Tab(text: 'Top'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: tabs));

    final CapsuleTrack track = tester.widget(find.byType(CapsuleTrack));
    expect(
      tester.getSize(find.byType(CapsuleTrack)).height,
      track.preferredSize.height,
    );
  });

  group('CapsuleActionCluster.labels', () {
    testWidgets('spells actions out from 600dp, icons below', (
      WidgetTester tester,
    ) async {
      bool? labels;
      Future<void> measure(double width) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: Builder(
              builder: (BuildContext context) {
                labels = CapsuleActionCluster.labels(context);
                return const SizedBox();
              },
            ),
          ),
        );
      }

      await measure(599);
      expect(labels, isFalse);
      await measure(600);
      expect(labels, isTrue);
    });
  });
}
