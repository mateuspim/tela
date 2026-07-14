import 'package:tela/domain/models/purity.dart';

/// The three privacy and availability levels available for image downloads.
///
/// ```dart
/// StorageTier.defaultFor(Purity.nsfw); // StorageTier.appPrivate
/// ```
enum StorageTier {
  /// A MediaStore image in `Pictures/tela`, visible to gallery applications.
  sharedGallery,

  /// A user-selected shared-storage directory with a `.nomedia` marker.
  filesOutsideGallery,

  /// An internal app file, unavailable to other apps and removed on uninstall.
  appPrivate;

  /// The privacy-preserving destination used before the user changes settings.
  static StorageTier defaultFor(Purity purity) {
    return purity == Purity.nsfw
        ? StorageTier.appPrivate
        : StorageTier.sharedGallery;
  }
}
