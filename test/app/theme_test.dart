import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/theme.dart';

/// Stands in for the palette Android hands `dynamic_color` on Monet devices.
ColorScheme _devicePalette(Brightness brightness) => ColorScheme.fromSeed(
  seedColor: const Color(0xFFB33771),
  brightness: brightness,
);

void main() {
  group('TelaTheme', () {
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

    group('accent override', () {
      const Color accent = Color(0xFF2C63E0);

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
