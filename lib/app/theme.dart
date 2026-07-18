import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// The app's Material 3 themes, built from the device palette when there is
/// one.
///
/// A wallpaper browser is a wall of other people's colour, so the chrome around
/// it stays deliberately quiet: near-neutral surfaces, and one accent used
/// sparingly for tela's own moments — the selected tab, the nav indicator, a
/// filled button. Material You is the default source of both: the chrome
/// borrows the colours the user already chose for their phone.
///
/// When the user picks a fixed accent, it overrides *only* those brand roles —
/// surfaces stay Material You — so identity survives on every device without
/// repainting the gallery wall. That splice is [_withAccent].
abstract final class TelaTheme {
  /// Seed colour used when the device has no palette to offer.
  ///
  /// Not dead code and not a placeholder: Monet is Android 12+, tela's minSdk
  /// is 29, and `dynamic_color` also yields nothing on a device whose OEM
  /// dropped the API. Roughly a tenth of supported devices land here.
  static const Color _seed = Color(0xFF7772E5);

  /// Light theme, from [device] when Android supplied a palette.
  ///
  /// ```dart
  /// DynamicColorBuilder(
  ///   builder: (ColorScheme? light, ColorScheme? dark) =>
  ///       MaterialApp(theme: TelaTheme.light(light)),
  /// );
  /// ```
  static ThemeData light(ColorScheme? device, {Color? accent}) =>
      _themeFrom(device, Brightness.light, accent);

  /// Dark theme. The default a wallpaper app should be judged in.
  static ThemeData dark(ColorScheme? device, {Color? accent}) =>
      _themeFrom(device, Brightness.dark, accent);

  /// Builds a theme from the device palette, or the seed when it cannot be
  /// used, then splices in the user's [accent] over the brand roles when set.
  ///
  /// A palette whose brightness does not match the one asked for is refused
  /// rather than adapted: rendering a light scheme in dark mode is how you get
  /// white-on-white text, and a wrong-but-neutral theme beats an unreadable
  /// one.
  static ThemeData _themeFrom(
    ColorScheme? device,
    Brightness brightness,
    Color? accent,
  ) {
    final ColorScheme base = _isUsable(device, brightness)
        ? device!.harmonized()
        : ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final ColorScheme scheme = accent == null
        ? base
        : _withAccent(base, accent, brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .55),
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: _inputBorder(),
        enabledBorder: _inputBorder(),
        focusedBorder: _inputBorder(color: scheme.primary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        height: 72,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        minWidth: 88,
        minExtendedWidth: 88,
        useIndicator: true,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicator: ShapeDecoration(
          color: scheme.secondaryContainer,
          shape: const StadiumBorder(),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: scheme.onSecondaryContainer,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelPadding: const EdgeInsets.symmetric(horizontal: 18),
        overlayColor: WidgetStatePropertyAll<Color>(
          scheme.primary.withValues(alpha: .08),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  /// Replaces [base]'s brand roles with a tonal palette grown from [accent],
  /// leaving its neutral surfaces untouched.
  ///
  /// The accent is used as-is, not `harmonized` toward the device:
  /// the user picked *this* colour, and shifting it toward their wallpaper is
  /// exactly the surprise a fixed accent exists to avoid. Only primary,
  /// secondary and tertiary (and their containers) move — surface, background,
  /// outline and error stay Material You, so photos still lead.
  static ColorScheme _withAccent(
    ColorScheme base,
    Color accent,
    Brightness brightness,
  ) {
    final ColorScheme a = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    return base.copyWith(
      primary: a.primary,
      onPrimary: a.onPrimary,
      primaryContainer: a.primaryContainer,
      onPrimaryContainer: a.onPrimaryContainer,
      secondary: a.secondary,
      onSecondary: a.onSecondary,
      secondaryContainer: a.secondaryContainer,
      onSecondaryContainer: a.onSecondaryContainer,
      tertiary: a.tertiary,
      onTertiary: a.onTertiary,
      tertiaryContainer: a.tertiaryContainer,
      onTertiaryContainer: a.onTertiaryContainer,
      inversePrimary: a.inversePrimary,
    );
  }

  static OutlineInputBorder _inputBorder({Color color = Colors.transparent}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: color),
    );
  }

  static bool _isUsable(ColorScheme? device, Brightness brightness) =>
      device != null && device.brightness == brightness;
}
