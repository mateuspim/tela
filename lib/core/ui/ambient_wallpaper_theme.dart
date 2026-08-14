import 'package:flutter/material.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/domain/models/ambient_seed.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

/// Themes its subtree in the colours of the wallpaper it is showing.
///
/// The one place tela's quiet-chrome rule is deliberately broken. It is safe
/// here and nowhere else: this wraps a screen whose subject is a *single*
/// photograph, so the surround taking that photograph's colour reads as the
/// image lighting the page. On a wall of thumbnails the same move would be the
/// chrome competing with sixty pictures at once — do not wrap a shelf in it.
///
/// Colour comes from [colors], the wallpaper's own dominant palette as its
/// source reported it, so there is no decode and no request behind the tint.
/// A wallpaper with nothing to seed from — every colour achromatic, or a source
/// that reports none at all — renders [child] under the app's ordinary theme
/// rather than under a grey one, which is why the tint is *absent* on Konachan
/// instead of broken there.
///
/// What it does **not** repaint is the error roles: the download affordance
/// warns in `ColorScheme.error` for a not-safe wallpaper, and a red wallpaper
/// must not be able to reshade its own warning. See [TelaTheme.ambient].
///
/// ```dart
/// AmbientWallpaperTheme(
///   colors: wallpaper.colors,
///   child: Scaffold(body: preview),
/// );
/// ```
class AmbientWallpaperTheme extends StatelessWidget {
  /// Themes [child] from [colors].
  const AmbientWallpaperTheme({
    required this.colors,
    required this.child,
    super.key,
  });

  /// The wallpaper's dominant colours, as `#rrggbb` strings.
  ///
  /// Taken from the listing model rather than the detail response, so a screen
  /// arrives already tinted instead of shifting under the user a beat later
  /// when its metadata fetch lands.
  final List<String> colors;

  /// The screen to paint.
  final Widget child;

  /// How long the surround takes to travel between two wallpapers' colours.
  ///
  /// Slower than a page turn on purpose: the tint is ambience, and a surround
  /// that snaps draws the eye off the image it exists to serve.
  static const Duration transition = Duration(milliseconds: 450);

  @override
  Widget build(BuildContext context) {
    final WallpaperColor? seed = ambientSeed(colors);
    if (seed == null) return child;
    return AnimatedTheme(
      data: TelaTheme.ambient(
        Theme.of(context).colorScheme,
        Color(0xFF000000 | seed.rgb),
      ),
      // A colour animation is the whole feature, so reduce-motion gets the
      // destination with no journey — the same collapse-to-a-cut the gallery
      // transitions and the skeleton's shimmer already make.
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : transition,
      child: child,
    );
  }
}
