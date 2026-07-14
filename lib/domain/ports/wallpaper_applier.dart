import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';

/// Applies a remote image to an Android wallpaper surface.
///
/// Implementations own downloading, decoding, and the platform call. Features
/// never import the wallpaper plugin directly.
abstract interface class WallpaperApplier {
  /// Downloads [imageUrl] and applies it to [target].
  ///
  /// Throws [WallpaperApplyFailure] for every operational failure and never
  /// includes [imageUrl] in the thrown value.
  Future<void> apply({
    required String imageUrl,
    required WallpaperTarget target,
  });
}
