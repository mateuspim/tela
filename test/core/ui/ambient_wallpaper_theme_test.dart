import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/ui/ambient_wallpaper_theme.dart';

/// Reads the theme one level below the ambient wrapper — which is the only
/// place it exists, and the reason every caller needs a [Builder].
ThemeData _themeUnder(WidgetTester tester) =>
    Theme.of(tester.element(find.byKey(_probe)));

const Key _probe = Key('ambient-probe');

/// `MaterialApp` builds an [AnimatedTheme] of its own, so every assertion about
/// *ours* has to say whose — an unscoped `find.byType` matches both and throws
/// "Too many elements" rather than failing with something readable.
final Finder _ambientTheme = find.descendant(
  of: find.byType(AmbientWallpaperTheme),
  matching: find.byType(AnimatedTheme),
);

Future<void> _pump(
  WidgetTester tester, {
  required List<String> colors,
  ThemeData? app,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        theme: app ?? TelaTheme.dark(null),
        home: AmbientWallpaperTheme(
          colors: colors,
          child: const SizedBox(key: _probe),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("paints the subtree in the wallpaper's own colour", (
    WidgetTester tester,
  ) async {
    await _pump(tester, colors: <String>['#0066cc']);

    expect(
      _themeUnder(tester).colorScheme.primary,
      TelaTheme.ambient(
        TelaTheme.dark(null).colorScheme,
        const Color(0xFF0066CC),
      ).colorScheme.primary,
    );
  });

  testWidgets('moves the surfaces, not only the accent', (
    WidgetTester tester,
  ) async {
    // The load-bearing claim of the whole slice. Splicing the brand roles the
    // way a fixed accent does would leave the scaffold, the cards and the app
    // bar on the untinted neutrals — a recoloured button on a grey page, which
    // is not what "the wallpaper lights the screen" means. Swap `ambient` for
    // a `copyWith(colorScheme:)` and this is the test that goes red.
    final ThemeData app = TelaTheme.dark(null);
    await _pump(tester, colors: <String>['#ff6600'], app: app);

    final ThemeData tinted = _themeUnder(tester);
    expect(tinted.colorScheme.surface, isNot(app.colorScheme.surface));
    expect(tinted.scaffoldBackgroundColor, tinted.colorScheme.surface);
  });

  testWidgets("keeps tela's component theming on the tinted scheme", (
    WidgetTester tester,
  ) async {
    // Both themes are built through one `_componentsOn`, so the tinted screen
    // cannot quietly lose the nav height or the flat app bar.
    await _pump(tester, colors: <String>['#993399']);

    final ThemeData tinted = _themeUnder(tester);
    expect(tinted.navigationBarTheme.height, 72);
    expect(tinted.appBarTheme.surfaceTintColor, Colors.transparent);
    expect(
      tinted.textTheme.headlineSmall?.fontFamily,
      TelaTheme.brandFontFamily,
    );
  });

  testWidgets('never repaints the warning roles', (WidgetTester tester) async {
    // `purityAlertTint` paints the download affordance in ColorScheme.error to
    // say "this wallpaper is not safe", and its own docstring calls error the
    // one warm role that cannot be repainted into the thing it warns against.
    // A scheme grown wholly from the seed breaks that: a dark-red wallpaper
    // reshades its own warning. Drop the copyWith in `ambient` and this fails.
    final ThemeData app = TelaTheme.dark(null);
    await _pump(tester, colors: <String>['#990000'], app: app);

    final ColorScheme tinted = _themeUnder(tester).colorScheme;
    expect(tinted.error, app.colorScheme.error);
    expect(tinted.onError, app.colorScheme.onError);
    // ...while everything decorative did move, so this is not just "no tint".
    expect(tinted.primary, isNot(app.colorScheme.primary));
  });

  testWidgets('leaves the app theme alone when nothing can seed a palette', (
    WidgetTester tester,
  ) async {
    // A greyscale wallpaper, and — the same path — every Konachan wallpaper,
    // whose mapper reports no colours at all. The screen must look ordinary,
    // never grey.
    final ThemeData app = TelaTheme.dark(null);
    await _pump(tester, colors: <String>['#000000', '#ffffff'], app: app);

    expect(_themeUnder(tester).colorScheme.primary, app.colorScheme.primary);
  });

  testWidgets('inserts no theme at all when there is nothing to tint', (
    WidgetTester tester,
  ) async {
    await _pump(tester, colors: const <String>[]);

    expect(_ambientTheme, findsNothing);
  });

  testWidgets('takes its brightness from the theme it sits under', (
    WidgetTester tester,
  ) async {
    // A dark scheme rendered under a light app is how you get white on white,
    // and the tint must not be the thing that introduces it.
    await _pump(
      tester,
      colors: <String>['#0066cc'],
      app: TelaTheme.light(null),
    );

    expect(_themeUnder(tester).colorScheme.brightness, Brightness.light);
  });

  testWidgets('crosses to the new colour rather than cutting to it', (
    WidgetTester tester,
  ) async {
    await _pump(tester, colors: <String>['#0066cc']);

    expect(
      tester.widget<AnimatedTheme>(_ambientTheme).duration,
      AmbientWallpaperTheme.transition,
    );
  });

  testWidgets('collapses the crossing to a cut under reduce motion', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      colors: <String>['#0066cc'],
      disableAnimations: true,
    );

    expect(
      tester.widget<AnimatedTheme>(_ambientTheme).duration,
      Duration.zero,
    );
  });
}
