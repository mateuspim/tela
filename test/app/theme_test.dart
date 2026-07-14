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
  });
}
