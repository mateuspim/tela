import 'package:tela/domain/models/wallpaper_color.dart';

/// The colour a wallpaper should paint its own screen with, or null for none.
///
/// Wallhaven reports a wallpaper's dominant colours already quantized to
/// [WallpaperColor.palette]'s 29 buckets, so this is a *choice among those*,
/// not colour extraction — it costs no decode and no request, and it is known
/// from the listing response before the detail fetch resolves.
///
/// Returns the first colour that can seed a palette at all. Null means "leave
/// the theme alone", and it is a real answer rather than a failure: a greyscale
/// wallpaper getting no tint is correct, where a greyscale wallpaper getting a
/// muddy tint is the bug.
///
/// ```dart
/// ambientSeed(wallpaper.colors)?.rgb; // 0x660000
/// ```
WallpaperColor? ambientSeed(List<String> colors) {
  for (final WallpaperColor colour in WallpaperColor.readAll(colors)) {
    if (!_isAchromatic(colour)) return colour;
  }
  return null;
}

/// Whether [colour] has no hue to grow a palette from.
///
/// Tested by *computing* the chroma rather than naming the four neutrals in
/// [WallpaperColor.palette], for the same reason `readAll` validates shape
/// instead of membership: Wallhaven reserves the right to change the API, and a
/// 30th grey should be refused by the rule that already exists rather than by a
/// list nobody remembered to widen.
///
/// A tonal palette grown from a grey seed is grey at every tone, so the screen
/// would spend an animation arriving somewhere indistinguishable from where it
/// started. Low chroma is fine and deliberately allowed through — `#424153`
/// seeds a muted slate, which is an honest answer for a muted wallpaper.
bool _isAchromatic(WallpaperColor colour) {
  final int rgb = colour.rgb;
  final int red = (rgb >> 16) & 0xFF;
  final int green = (rgb >> 8) & 0xFF;
  final int blue = rgb & 0xFF;
  return red == green && green == blue;
}
