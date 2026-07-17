import 'package:tela/domain/models/crop_region.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';

/// Applies a user-framed crop of a [Wallpaper] to one Android surface.
///
/// The in-app counterpart to `AdjustWallpaper`: both let the user choose the
/// crop, but that one hands the image to the OEM's editor — a separate app — so
/// it refuses explicit wallpapers. This one decodes and sets the region inside
/// tela's own process, so **it has no purity gate**: an explicit wallpaper is
/// as safe here as through `ApplyWallpaper`, its pixels never leaving the app.
class ApplyCroppedWallpaper {
  /// Creates the use case over the platform-independent [applier] port.
  const ApplyCroppedWallpaper({required WallpaperApplier applier})
    : _applier = applier;

  final WallpaperApplier _applier;

  /// Applies [region] of [wallpaper]'s full-resolution image to [target].
  Future<void> call(
    Wallpaper wallpaper,
    CropRegion region,
    WallpaperTarget target,
  ) {
    return _applier.applyRegion(
      source: Uri.parse(wallpaper.fullImageUrl),
      target: target,
      region: region,
    );
  }
}
