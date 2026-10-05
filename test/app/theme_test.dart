import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/theme.dart';

/// Stands in for the palette Android hands `dynamic_color` on Monet devices.
ColorScheme _devicePalette(Brightness brightness) => ColorScheme.fromSeed(
  seedColor: const Color(0xFFB33771),
  brightness: brightness,
);

/// The shape `dynamic_color` 1.8.1 really hands over: its CorePalette mapping
/// sets `surface` but no `surfaceContainer*`/`surfaceBright`/`surfaceDim`, so
/// every one of those defaults to `surface`.
ColorScheme _collapsedDevicePalette() => const ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFBFC2FF),
  onPrimary: Color(0xFF282B60),
  secondary: Color(0xFFC5C5DD),
  onSecondary: Color(0xFF2E2F42),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  surface: Color(0xFF1A1B20),
  onSurface: Color(0xFFE4E1E9),
);

void main() {
  group('TelaTheme', () {
    test('fills the surface tones a Monet palette arrives without', () {
      // SM-X730, 2026-10-05: band, capsules and grid all painted #1a1b20.
      final ColorScheme scheme = TelaTheme.dark(
        _collapsedDevicePalette(),
      ).colorScheme;

      expect(scheme.surface, _collapsedDevicePalette().harmonized().surface);
      expect(scheme.surfaceContainerHighest, isNot(scheme.surface));
      expect(
        scheme.surfaceBright.computeLuminance(),
        greaterThan(scheme.surface.computeLuminance()),
      );
    });

    test('leaves a palette that already has surface tones alone', () {
      final ColorScheme device = _devicePalette(Brightness.dark).harmonized();

      final ColorScheme scheme = TelaTheme.dark(device).colorScheme;

      expect(scheme.surfaceContainerHigh, device.surfaceContainerHigh);
    });

    test('uses the device palette when Android supplies one', () {
      final ColorScheme device = _devicePalette(Brightness.dark);

      final ThemeData theme = TelaTheme.dark(device);

      expect(theme.colorScheme.primary, device.harmonized().primary);
    });

    test('falls back to the seed when there is no device palette', () {
      // Monet is Android 12+; tela's minSdk is 29, so this is a live path.
      final ThemeData theme = TelaTheme.dark(null);

      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(
        theme.colorScheme.primary,
        isNot(
          _devicePalette(
            Brightness.dark,
          ).primary,
        ),
      );
    });

    test('refuses a device palette of the wrong brightness', () {
      // Rendering a light scheme in dark mode is how you get white on white.
      final ThemeData theme = TelaTheme.dark(_devicePalette(Brightness.light));

      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('themes both brightnesses at the brightness asked for', () {
      expect(
        TelaTheme.light(
          _devicePalette(Brightness.light),
        ).colorScheme.brightness,
        Brightness.light,
      );
      expect(
        TelaTheme.dark(_devicePalette(Brightness.dark)).colorScheme.brightness,
        Brightness.dark,
      );
    });

    test('keeps the chrome quiet: the app bar does not tint', () {
      final ThemeData theme = TelaTheme.dark(_devicePalette(Brightness.dark));

      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      expect(theme.appBarTheme.backgroundColor, theme.colorScheme.surface);
    });

    group('stronger selected states', () {
      final ThemeData theme = TelaTheme.dark(_devicePalette(Brightness.dark));
      final ColorScheme scheme = theme.colorScheme;

      test('the nav bar indicator wears the brand primary', () {
        // Off Material's default secondaryContainer: selection is tela's.
        expect(
          theme.navigationBarTheme.indicatorColor,
          scheme.primaryContainer,
        );
        expect(
          theme.navigationBarTheme.indicatorColor,
          isNot(scheme.secondaryContainer),
        );
      });

      test('the rail and the sorting tabs select on the same accent pill', () {
        final ShapeDecoration tab =
            theme.tabBarTheme.indicator! as ShapeDecoration;

        expect(
          theme.navigationRailTheme.indicatorColor,
          scheme.primaryContainer,
        );
        expect(tab.color, scheme.primaryContainer);
      });

      test('the selected destination gains weight, not only colour', () {
        // A user who cannot split the two container tones by hue still sees it.
        final TextStyle selected = theme.navigationBarTheme.labelTextStyle!
            .resolve(<WidgetState>{WidgetState.selected})!;
        final TextStyle idle = theme.navigationBarTheme.labelTextStyle!.resolve(
          <WidgetState>{},
        )!;

        expect(selected.fontWeight, FontWeight.w600);
        expect(idle.fontWeight, FontWeight.w500);
      });

      test('the selected icon reads on the accent indicator', () {
        final IconThemeData selected = theme.navigationBarTheme.iconTheme!
            .resolve(<WidgetState>{WidgetState.selected})!;

        expect(selected.color, scheme.onPrimaryContainer);
      });
    });

    group('accent override', () {
      const Color accent = Color(0xFF2C63E0);

      test('is what the nav selection carries', () {
        // The whole point of the splice: selection is where the brand shows.
        final ThemeData theme = TelaTheme.dark(
          _devicePalette(Brightness.dark),
          accent: accent,
        );
        final Color fromAccent = ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).primaryContainer;

        expect(theme.navigationBarTheme.indicatorColor, fromAccent);
      });

      test('paints the brand roles from the chosen accent, used as-is', () {
        // Grown straight from the accent, not harmonized toward the device —
        // the user picked this colour and must get this colour.
        final ThemeData theme = TelaTheme.dark(
          _devicePalette(Brightness.dark),
          accent: accent,
        );
        final ColorScheme fromAccent = ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        );

        expect(theme.colorScheme.primary, fromAccent.primary);
        expect(
          theme.colorScheme.secondaryContainer,
          fromAccent.secondaryContainer,
        );
      });

      test('leaves the neutral surfaces on Material You, so photos lead', () {
        final ColorScheme device = _devicePalette(Brightness.dark);
        final ThemeData plain = TelaTheme.dark(device);
        final ThemeData tinted = TelaTheme.dark(device, accent: accent);

        // The wall stays the device's; only the brand roles moved.
        expect(tinted.colorScheme.surface, plain.colorScheme.surface);
        expect(
          tinted.colorScheme.surfaceContainer,
          plain.colorScheme.surfaceContainer,
        );
        expect(tinted.colorScheme.primary, isNot(plain.colorScheme.primary));
      });

      test('a null accent is exactly the device palette, unchanged', () {
        final ColorScheme device = _devicePalette(Brightness.light);

        expect(
          TelaTheme.light(device).colorScheme.primary,
          // Passing null explicitly is the behaviour under test: it must equal
          // the no-accent form.
          // ignore: avoid_redundant_argument_values
          TelaTheme.light(device, accent: null).colorScheme.primary,
        );
      });

      test('overrides the seed fallback too, on a Monet-less device', () {
        final ThemeData theme = TelaTheme.dark(null, accent: accent);
        final ColorScheme fromAccent = ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        );

        expect(theme.colorScheme.primary, fromAccent.primary);
      });
    });
  });
}
