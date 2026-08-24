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
  /// tela's own colour: the seed for the fallback palette, and the fixed ink
  /// of the brand marks.
  ///
  /// Two jobs, one constant. As a *seed* it is not dead code and not a
  /// placeholder: Monet is Android 12+, tela's minSdk is 29, and
  /// `dynamic_color` also yields nothing on a device whose OEM dropped the
  /// API. Roughly a tenth of supported devices land here.
  ///
  /// As *ink* it is what `TelaMark` draws in, and it is deliberately not
  /// `ColorScheme.primary`: the accent belongs to the user (see [_withAccent])
  /// and identity must not move with it. The same value is spelled again in
  /// `android/app/src/main/res/values/tela_brand.xml`, for the launcher icon
  /// and the splash — surfaces Android paints before Dart exists. `docs/BRAND.md`
  /// records that those two must stay in step.
  ///
  /// ```dart
  /// const TelaMark(size: 24, color: TelaTheme.brandSeed);
  /// ```
  static const Color brandSeed = Color(0xFF7772E5);

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
        : ColorScheme.fromSeed(seedColor: brandSeed, brightness: brightness);
    final ColorScheme scheme = accent == null
        ? base
        : _withAccent(base, accent, brightness);
    return _componentsOn(scheme);
  }

  /// The theme one wallpaper paints its own screen with, grown from [seed].
  ///
  /// Unlike [_withAccent], which splices the brand roles and leaves Material
  /// You's neutrals alone, this rebuilds the *whole* scheme: on a screen whose
  /// subject is a single photograph the surfaces are meant to move too, which
  /// is what makes the tint read as the image lighting the page rather than as
  /// a recoloured button. Everywhere else the quiet-chrome rule still holds —
  /// see the class docstring, and `AmbientWallpaperTheme` for the one caller.
  ///
  /// The user's fixed accent is deliberately *not* preserved here. That accent
  /// answers "which colour is tela's", and this screen is answering a different
  /// question. Identity is untouched either way: `TelaMark` draws in
  /// [brandSeed] and never in `ColorScheme.primary`.
  ///
  /// **[base]'s error roles are held back, and that is load-bearing.** They are
  /// semantic, not decorative: `purityAlertTint` paints the download
  /// affordance in `ColorScheme.error` to say *this wallpaper is not safe*, and
  /// its docstring already claims error is "the one warm role that cannot be
  /// repainted into the very accent it is warning against". A scheme grown
  /// wholly from the seed breaks that claim — a dark-red wallpaper reshades its
  /// own warning, and at worst tints it to match the surface it sits on. Caught
  /// by *the download button warns before a not-safe wallpaper lands*, which
  /// goes red the moment these four are dropped.
  ///
  /// Built through the same [_componentsOn] as every other theme, so a card
  /// radius or a nav height added there cannot go missing on a tinted screen.
  ///
  /// **A null [seed] is the untinted theme, and it is not a convenience.** It
  /// is what lets `AmbientWallpaperTheme` keep one `AnimatedTheme` in the tree
  /// whether or not there is a colour to wear — the shape stability that
  /// widget's `build` explains — and it has to come out of [_componentsOn] to
  /// do it: `ThemeData.lerp` refuses two text themes whose `inherit` disagree,
  /// so tweening a raw ambient theme against a *localized* `Theme.of` result
  /// throws. Rebuilding [base] here gives the tween two themes of the same
  /// make, which is the only kind it can interpolate.
  ///
  /// ```dart
  /// TelaTheme.ambient(Theme.of(context).colorScheme, const Color(0xFF660000));
  /// TelaTheme.ambient(Theme.of(context).colorScheme, null); // no tint
  /// ```
  static ThemeData ambient(ColorScheme base, Color? seed) {
    if (seed == null) return _componentsOn(base);
    final ColorScheme tinted = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: base.brightness,
    );
    return _componentsOn(
      tinted.copyWith(
        error: base.error,
        onError: base.onError,
        errorContainer: base.errorContainer,
        onErrorContainer: base.onErrorContainer,
      ),
    );
  }

  /// Dresses [scheme] in tela's component theming.
  ///
  /// The single place components are styled. Both entry points — the app's own
  /// theme and [ambient] — come through here, because the failure mode of two
  /// builders is a screen whose scheme moved while its scaffold background,
  /// card colour and app bar stayed behind, which reads as a rendering bug
  /// rather than as a theme.
  static ThemeData _componentsOn(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _brandText(scheme.brightness),
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
      navigationBarTheme: _navigationBarTheme(scheme),
      navigationRailTheme: _navigationRailTheme(scheme),
      tabBarTheme: _tabBarTheme(scheme),
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

  /// The bottom navigation bar, with selection carried on the brand accent.
  ///
  /// The indicator moves off Material's default `secondaryContainer` onto
  /// [ColorScheme.primaryContainer] so the destination you are on wears tela's
  /// own colour, not a muted grey-tint — one of the accent moments this theme
  /// spends on deliberately. The selected label also gains weight, so selection
  /// survives for a user who cannot separate the two container tones by hue.
  static NavigationBarThemeData _navigationBarTheme(ColorScheme scheme) {
    return NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      height: 72,
      elevation: 0,
      iconTheme: _selectedIconColor(scheme),
      labelTextStyle: _selectedLabelStyle(scheme),
    );
  }

  /// The wide-screen navigation rail, matching the bar's selected language.
  static NavigationRailThemeData _navigationRailTheme(ColorScheme scheme) {
    return NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      minWidth: 88,
      minExtendedWidth: 88,
      useIndicator: true,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    );
  }

  /// The Browse sorting tabs, selected on the same accent pill as the nav.
  static TabBarThemeData _tabBarTheme(ColorScheme scheme) {
    return TabBarThemeData(
      dividerColor: Colors.transparent,
      indicator: ShapeDecoration(
        color: scheme.primaryContainer,
        shape: const StadiumBorder(),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: scheme.onPrimaryContainer,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      labelPadding: const EdgeInsets.symmetric(horizontal: 18),
      overlayColor: WidgetStatePropertyAll<Color>(
        scheme.primary.withValues(alpha: .08),
      ),
    );
  }

  /// Icon colour that reads on the accent indicator when selected, quiet when
  /// not — for [NavigationBar], whose icon theme is state-resolved.
  static WidgetStateProperty<IconThemeData> _selectedIconColor(
    ColorScheme scheme,
  ) {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      final bool selected = states.contains(WidgetState.selected);
      return IconThemeData(
        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      );
    });
  }

  /// Label style that weights the selected destination, for [NavigationBar].
  static WidgetStateProperty<TextStyle> _selectedLabelStyle(
    ColorScheme scheme,
  ) {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      final bool selected = states.contains(WidgetState.selected);
      return TextStyle(
        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      );
    });
  }

  /// The display face — [brandFontFamily] — on the display and headline roles,
  /// leaving title, body and label on the device font.
  ///
  /// The split is the whole design: tela speaks in Bricolage Grotesque for its
  /// own moments (a screen title, the wordmark, a shelf plaque) and in the
  /// user's own font everywhere they are reading or operating, so the chrome
  /// keeps an identity without turning paragraphs into a typeface demo. The
  /// tighter tracking is what a grotesque display face wants at size; the body
  /// roles keep Material's own metrics.
  static TextTheme _brandText(Brightness brightness) {
    final TextTheme base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    return base.copyWith(
      displayLarge: _display(base.displayLarge, -1.5),
      displayMedium: _display(base.displayMedium, -1),
      displaySmall: _display(base.displaySmall, -0.5),
      headlineLarge: _display(base.headlineLarge, -0.5),
      headlineMedium: _display(base.headlineMedium, -0.4),
      headlineSmall: _display(base.headlineSmall, -0.3),
    );
  }

  /// One display/headline slot in [brandFontFamily], at [letterSpacing].
  static TextStyle? _display(TextStyle? base, double letterSpacing) =>
      base?.copyWith(
        fontFamily: brandFontFamily,
        fontWeight: FontWeight.w600,
        letterSpacing: letterSpacing,
      );

  /// The bundled display family (see `pubspec.yaml`). Brand moments only.
  static const String brandFontFamily = 'Bricolage';

  static OutlineInputBorder _inputBorder({Color color = Colors.transparent}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: color),
    );
  }

  static bool _isUsable(ColorScheme? device, Brightness brightness) =>
      device != null && device.brightness == brightness;
}
