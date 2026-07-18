import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';

void main() {
  group('WallpaperGridSkeleton', () {
    testWidgets('previews the wall as a masonry, not a lone spinner', (
      WidgetTester tester,
    ) async {
      await _pump(tester);

      // A packed placeholder wall, laid out ahead of the real images.
      expect(find.byType(AspectRatio), findsNWidgets(12));
      // The whole point of the slice: no centred spinner over an empty screen.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('carries the loading label but hides the placeholder tiles', (
      WidgetTester tester,
    ) async {
      await _pump(tester);

      expect(find.bySemanticsLabel('Loading wallpapers'), findsOneWidget);
    });

    testWidgets('shimmers while motion is allowed', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      // Never pumpAndSettle: the sweep repeats forever and would time out.
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(ShaderMask), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('rests static under reduced motion', (
      WidgetTester tester,
    ) async {
      await _pump(tester, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 200));

      // No sweep to paint, and nothing left animating behind the wall.
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          disableAnimations: reduceMotion,
        ),
        child: const Scaffold(body: WallpaperGridSkeleton()),
      ),
    ),
  );
  await tester.pump();
}
