import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';

/// Applies a selected [Wallpaper] to one Android surface.
class ApplyWallpaper {
  /// Creates the use case over the platform-independent [applier] port.
  const ApplyWallpaper({required WallpaperApplier applier})
    : _applier = applier;

  final WallpaperApplier _applier;

  /// Applies [wallpaper] to [target] using its full-resolution image.
  Future<void> call(Wallpaper wallpaper, WallpaperTarget target) {
    return _applier.apply(
      source: Uri.parse(wallpaper.fullImageUrl),
      target: target,
    );
  }
}
