/// Stable route names and paths shared by navigation call sites.
abstract final class TelaRoutes {
  /// Browse grid path.
  static const String browsePath = '/';

  /// Browse grid route name.
  static const String browseName = 'browse';

  /// Detail path, including the Wallhaven id parameter.
  static const String detailPath = '/wallpaper/:wallpaperId';

  /// Detail route name.
  static const String detailName = 'wallpaper-detail';

  /// Settings path.
  static const String settingsPath = '/settings';

  /// Settings route name.
  static const String settingsName = 'settings';

  /// Favorites path.
  static const String favoritesPath = '/favorites';

  /// Favorites route name.
  static const String favoritesName = 'favorites';

  /// Private library path.
  static const String privateLibraryPath = '/private';

  /// Private library route name.
  static const String privateLibraryName = 'private-library';

  /// Path of a listing followed from a wallpaper — a tag's, or an uploader's.
  static const String linkedListingPath = '/listing';

  /// Linked-listing route name.
  static const String linkedListingName = 'linked-listing';

  /// Download history path.
  static const String downloadHistoryPath = '/downloads';

  /// Download history route name.
  static const String downloadHistoryName = 'download-history';
}
