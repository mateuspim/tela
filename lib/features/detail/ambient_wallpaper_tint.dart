import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/ui/ambient_wallpaper_theme.dart';
import 'package:tela/domain/models/ambient_seed.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

/// The colour a wallpaper's own pixels are mostly made of, for tinting.
///
/// Keyed by thumbnail URL rather than by wallpaper, so two shelves showing the
/// same image share one read. Only ever watched for a source that reported no
/// palette — see [AmbientWallpaperTint] — so Wallhaven never spends a decode on
/// a question its own JSON already answered.
final FutureProviderFamily<WallpaperColor?, String> ambientFallbackProvider =
    FutureProvider.autoDispose.family<WallpaperColor?, String>(
      (Ref ref, String thumbnailUrl) =>
          ref.watch(dominantColorProvider).of(thumbnailUrl),
    );

/// Paints [child] in [wallpaper]'s own colour, decoding one only if it must.
///
/// Both surfaces that show a single wallpaper large come through here — the
/// Detail screen and the fullscreen viewer it opens — because the fullscreen
/// viewer is a *pushed route*: it is built under the Navigator, above Detail,
/// so it inherits nothing from the theme Detail wrapped itself in and has to
/// ask for the tint itself.
///
/// ```dart
/// AmbientWallpaperTint(wallpaper: wallpaper, child: viewer);
/// ```
class AmbientWallpaperTint extends ConsumerWidget {
  /// Tints [child] in [wallpaper]'s colours.
  const AmbientWallpaperTint({
    required this.wallpaper,
    required this.child,
    super.key,
  });

  /// The wallpaper whose palette lights the surround.
  final Wallpaper wallpaper;

  /// The screen to paint.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AmbientWallpaperTheme(
      colors: wallpaper.colors,
      fallbackSeed: _fallbackSeed(ref),
      child: child,
    );
  }

  /// A colour read from the wallpaper itself, for a source that reports none.
  ///
  /// Watched only when there is nothing to read from the listing, so Wallhaven
  /// — which answers this in its own JSON — never decodes a pixel for it. The
  /// read is asynchronous, so the screen paints untinted for the frames it
  /// takes and arrives at its colour a beat later; that beat is why this is a
  /// fallback and not the primary path.
  WallpaperColor? _fallbackSeed(WidgetRef ref) {
    if (ambientSeed(wallpaper.colors) != null) return null;
    return ref.watch(ambientFallbackProvider(wallpaper.thumbOriginalUrl)).value;
  }
}
