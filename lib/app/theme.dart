import 'package:flutter/material.dart';

/// The app's Material 3 themes.
///
/// A wallpaper browser is a wall of other people's colour, so the chrome around
/// it stays deliberately quiet: near-neutral surfaces, no competing accent.
/// Material You (`dynamic_color`) replaces the seed in Wave 2.
abstract final class TelaTheme {
  /// Seed colour used until the system palette is read (Wave 2).
  static const Color _seed = Color(0xFF6B7A8F);

  /// Light theme.
  static ThemeData get light => _themeFor(Brightness.light);

  /// Dark theme. The default a wallpaper app should be judged in.
  static ThemeData get dark => _themeFor(Brightness.dark);

  static ThemeData _themeFor(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
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
}
