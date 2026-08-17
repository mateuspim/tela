import 'package:flutter/material.dart';

/// The scrim and the ink an immersive gallery surface paints its chrome with.
///
/// The viewer's controls used to hardcode `Colors.black45` in six places with
/// `Colors.white` on top, which is why the fullscreen surface stayed a black
/// void while the Detail screen it opens from paints itself in the wallpaper's
/// own colour (see `AmbientWallpaperTheme`). Reading the scheme instead lets
/// one code path serve both: Detail's session wraps the viewer in the ambient
/// theme and the chrome arrives tinted, while the private library and the
/// download viewer wrap it in nothing and keep the app's neutral scheme —
/// which is very close to the black they render today, and deliberately so.
///
/// **The scrim darkens toward the seed, it never lightens toward it**, and that
/// is the whole reason this is a blend rather than `surface.withValues`. L2b
/// measured the phone bar's white controls at 2.9–3.1:1 against a genuinely
/// pale wallpaper — clearing the 3:1 floor for UI graphics and nothing more.
/// A scrim that took a light wallpaper's colour directly would spend the only
/// margin there is, on the surface where the wallpaper is largest.
///
/// ```dart
/// final ImmersiveChromePalette chrome = ImmersiveChromePalette.of(context);
/// DecoratedBox(decoration: BoxDecoration(color: chrome.scrim), ...);
/// ```
@immutable
class ImmersiveChromePalette {
  const ImmersiveChromePalette._({
    required this.scrim,
    required this.ink,
    required this.disabledInk,
  });

  /// Resolves the chrome's colours from the ambient [ColorScheme].
  factory ImmersiveChromePalette.of(BuildContext context) {
    return ImmersiveChromePalette.fromScheme(Theme.of(context).colorScheme);
  }

  /// Resolves the chrome's colours from [scheme], for tests and for callers
  /// that already hold one.
  factory ImmersiveChromePalette.fromScheme(ColorScheme scheme) {
    final Color tintedBlack = Color.alphaBlend(
      scheme.surface.withValues(alpha: _seedShare),
      Colors.black,
    );
    return ImmersiveChromePalette._(
      scrim: tintedBlack.withValues(alpha: _scrimAlpha),
      ink: scheme.onSurface,
      disabledInk: scheme.onSurface.withValues(alpha: _disabledAlpha),
    );
  }

  /// How much of the wallpaper's colour survives the blend into black.
  ///
  /// A third is enough to read as tinted beside the untinted app and little
  /// enough that a pale wallpaper's scrim is still a dark one. It is a share of
  /// the *hue*, not of the opacity — [_scrimAlpha] is unchanged from the
  /// `Colors.black45` these replaced, so the chrome hides exactly as much of
  /// the picture as it did before.
  static const double _seedShare = 0.35;

  /// `Colors.black45`'s own alpha, to the byte rather than to the name — the
  /// constant is `0x73`, which is 0.451 and not the 0.45 it is called.
  static const double _scrimAlpha = 0x73 / 0xFF;

  /// `Colors.white38`'s own alpha, for a control at a gallery boundary. Same
  /// story: the byte is `0x62`, or 0.384.
  static const double _disabledAlpha = 0x62 / 0xFF;

  /// What the chrome sits on: near-black, carrying the wallpaper's hue.
  final Color scrim;

  /// What the chrome is drawn in — icons, the position count, an arrow.
  final Color ink;

  /// [ink] for a control that cannot be pressed, such as *Next* at the end of
  /// a loaded gallery.
  final Color disabledInk;

  @override
  bool operator ==(Object other) {
    return other is ImmersiveChromePalette &&
        other.scrim == scrim &&
        other.ink == ink &&
        other.disabledInk == disabledInk;
  }

  @override
  int get hashCode => Object.hash(scrim, ink, disabledInk);
}
