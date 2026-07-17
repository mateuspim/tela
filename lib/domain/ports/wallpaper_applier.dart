import 'package:tela/domain/models/crop_region.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';

/// Applies an image to an Android wallpaper surface.
///
/// Implementations own reading the source, decoding, and the platform call.
/// Features never import the wallpaper plugin directly.
abstract interface class WallpaperApplier {
  /// Reads [source] and applies it to [target].
  ///
  /// [source] is either a remote Wallhaven URL or the local URI a past download
  /// landed at — an already-downloaded wallpaper is set again from the file on
  /// disk, not fetched a second time. A source that cannot be read raises
  /// [WallpaperApplyProblem.source], which is what tells a caller holding both
  /// that the local one is gone.
  ///
  /// Throws [WallpaperApplyFailure] for every operational failure and never
  /// includes [source] in the thrown value.
  Future<void> apply({
    required Uri source,
    required WallpaperTarget target,
  });

  /// Reads [source], crops it to [region], and applies that crop to [target].
  ///
  /// [region] is in [source]'s own pixel space — the sub-rect tela's crop
  /// editor framed. The adapter decodes only that region (never the whole 6K
  /// image) and sets it deterministically, unlike [apply], which hands the full
  /// image to the platform and lets it choose the crop.
  ///
  /// The pixels never leave the app — decode and set happen in tela's own
  /// process — so this path serves explicit wallpapers too, which `apply`'s
  /// export-refusing siblings (the system editor, the image share) may not.
  ///
  /// Throws [WallpaperApplyFailure] for every operational failure and never
  /// includes [source] in the thrown value.
  Future<void> applyRegion({
    required Uri source,
    required WallpaperTarget target,
    required CropRegion region,
  });
}
