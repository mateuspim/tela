import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';

/// Sets an app-private wallpaper, from the file only tela can open.
///
/// The private counterpart to `ApplyDownload`, and deliberately simpler: a
/// private file has no public Wallhaven URL to fall back on — falling back
/// would mean re-fetching an explicit image over the network, which this tier
/// exists to avoid — so it applies the local URI and lets a read failure
/// surface as an ordinary apply failure.
///
/// ```dart
/// await applyPrivateImage(image, WallpaperTarget.both);
/// ```
class ApplyPrivateImage {
  /// Creates the use case over the platform-independent [applier] port.
  const ApplyPrivateImage({required WallpaperApplier applier})
    : _applier = applier;

  final WallpaperApplier _applier;

  /// Applies [image] to [target], reading the app-private file on this device.
  Future<void> call(PrivateImage image, WallpaperTarget target) async {
    await _applier.apply(source: image.location, target: target);
  }
}
