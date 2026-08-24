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
/// instead of broken there. Absent, but still through the same wrapper — see
/// [build] for why the untinted case may not take a shortcut.
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
    this.fallbackSeed,
    super.key,
  });

  /// The wallpaper's dominant colours, as `#rrggbb` strings.
  ///
  /// Taken from the listing model rather than the detail response, so a screen
  /// arrives already tinted instead of shifting under the user a beat later
  /// when its metadata fetch lands.
  final List<String> colors;

  /// A colour to use when [colors] yields none, for a source that reports no
  /// palette of its own.
  ///
  /// Read from the wallpaper's own pixels — see `DominantColor` — and passed in
  /// rather than fetched here, because that read is asynchronous and `core/ui`
  /// may not reach up into a feature's providers to await it. Null keeps the
  /// old behaviour exactly: no palette and no fallback means no tint.
  final WallpaperColor? fallbackSeed;

  /// The screen to paint.
  final Widget child;

  /// How long the surround takes to travel between two wallpapers' colours.
  ///
  /// Slower than a page turn on purpose: the tint is ambience, and a surround
  /// that snaps draws the eye off the image it exists to serve.
  static const Duration transition = Duration(milliseconds: 450);

  /// Always an [AnimatedTheme], **including when there is no tint at all.**
  ///
  /// It used to return [child] bare in that case, and the shape of the tree
  /// was the bug. [fallbackSeed] arrives asynchronously, so a Konachan screen
  /// builds untinted first and tinted a beat later — and going from `child` to
  /// `AnimatedTheme > child` is not an update, it is a *re-inflation*: every
  /// element below here is torn down and rebuilt from scratch, losing its
  /// State. It cost the tint its own crossfade on exactly the path that needs
  /// one, and on 2026-08-24 it started throwing, when Detail's facts sheet
  /// gained a `DraggableScrollableController` — the replacement sheet attaches
  /// in the same frame the old one is still holding, which the framework
  /// asserts against.
  ///
  /// The untinted case therefore goes through [TelaTheme.ambient] too, with a
  /// null seed — see there for why it may not simply hand back `Theme.of`. The
  /// scheme it resolves to is the ancestor's own, so nothing about an untinted
  /// screen's colours changes; only the instance does.
  @override
  Widget build(BuildContext context) {
    final ThemeData ordinary = Theme.of(context);
    final WallpaperColor? seed = ambientSeed(colors) ?? fallbackSeed;
    return AnimatedTheme(
      data: TelaTheme.ambient(
        ordinary.colorScheme,
        seed == null ? null : Color(0xFF000000 | seed.rgb),
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
