/// The three privacy and availability levels available for image downloads.
///
/// Which tier a wallpaper goes to is a user setting, not a property of the
/// tier: see `StorageSettings.tierFor`.
enum StorageTier {
  /// A MediaStore image in `Pictures/tela`, visible to gallery applications.
  sharedGallery,

  /// A user-selected shared-storage directory with a `.nomedia` marker.
  filesOutsideGallery,

  /// An internal app file, unavailable to other apps and removed on uninstall.
  appPrivate,
}
