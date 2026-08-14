import 'package:tela/domain/models/wallpaper_color.dart';

/// Reads the colour an image is mostly made of.
///
/// Exists for the sources that report no palette of their own — Konachan sends
/// none at all — so their wallpapers can tint a detail screen the way
/// Wallhaven's do. A port rather than a call, because the only implementation
/// decodes pixels through `dart:ui` and touches the on-disk thumbnail cache,
/// neither of which belongs in a widget or a use case.
///
/// ```dart
/// final WallpaperColor? seed =
///     await dominantColor.of(wallpaper.thumbOriginalUrl);
/// ```
abstract interface class DominantColor {
  /// The dominant colour of the image at [imageUrl], or null when it has none.
  ///
  /// Null is a real answer and never an error: a greyscale photograph has no
  /// colour to seed a palette with, and so does an image that cannot be
  /// fetched. Both leave the screen on the app's ordinary theme, which is the
  /// same place a Wallhaven wallpaper of four greys ends up.
  Future<WallpaperColor?> of(String imageUrl);
}
