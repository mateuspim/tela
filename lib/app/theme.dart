import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// The app's Material 3 themes, built from the device palette when there is
/// one.
///
/// A wallpaper browser is a wall of other people's colour, so the chrome around
/// it stays deliberately quiet: near-neutral surfaces, no competing accent.
/// Material You only widens that idea — the chrome borrows the colours the user
/// already chose for their phone instead of ones tela invented.
abstract final class TelaTheme {
  /// Seed colour used when the device has no palette to offer.
  ///
  /// Not dead code and not a placeholder: Monet is Android 12+, tela's minSdk
  /// is 29, and `dynamic_color` also yields nothing on a device whose OEM
  /// dropped the API. Roughly a tenth of supported devices land here.
  static const Color _seed = Color(0xFF6B7A8F);

  /// Light theme, from [device] when Android supplied a palette.
  ///
  /// ```dart
  /// DynamicColorBuilder(
  ///   builder: (ColorScheme? light, ColorScheme? dark) =>
  ///       MaterialApp(theme: TelaTheme.light(light)),
  /// );
  /// ```
  static ThemeData light(ColorScheme? device) =>
      _themeFrom(device, Brightness.light);

  /// Dark theme. The default a wallpaper app should be judged in.
  static ThemeData dark(ColorScheme? device) =>
      _themeFrom(device, Brightness.dark);

  /// Builds a theme from the device palette, or the seed when it cannot be
  /// used.
  ///
  /// A palette whose brightness does not match the one asked for is refused
  /// rather than adapted: rendering a light scheme in dark mode is how you get
  /// white-on-white text, and a wrong-but-neutral theme beats an unreadable
  /// one.
  static ThemeData _themeFrom(ColorScheme? device, Brightness brightness) {
    final ColorScheme scheme = _isUsable(device, brightness)
        ? device!.harmonized()
        : ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }

  static bool _isUsable(ColorScheme? device, Brightness brightness) =>
      device != null && device.brightness == brightness;
}
