/// Stable route names and paths shared by navigation call sites.
abstract final class TelaRoutes {
  /// Browse grid path.
  static const String browsePath = '/';

  /// Browse grid route name.
  static const String browseName = 'browse';

  /// Detail path, including the Wallhaven id parameter.
  static const String detailPath = '/wallpaper/:wallpaperKey';

  /// Detail route name.
  static const String detailName = 'wallpaper-detail';

  /// Settings path.
  static const String settingsPath = '/settings';

  /// Settings route name.
  static const String settingsName = 'settings';

  /// Library path — the tab hubbing favorites, history, and the private tier.
  static const String libraryPath = '/library';

  /// Library route name.
  static const String libraryName = 'library';

  /// Private library path.
  static const String privateLibraryPath = '/private';

  /// Private library route name.
  static const String privateLibraryName = 'private-library';

  /// Path of the secure, local-only viewer over the private library.
  static const String privateViewerPath = '/private/view';

  /// Private-library viewer route name.
  static const String privateViewerName = 'private-viewer';

  /// Path of a listing followed from a wallpaper — a tag's, or an uploader's.
  static const String linkedListingPath = '/listing';

  /// Linked-listing route name.
  static const String linkedListingName = 'linked-listing';

  /// Download history path.
  static const String downloadHistoryPath = '/downloads';

  /// Download history route name.
  static const String downloadHistoryName = 'download-history';

  /// Path of the screen that moves already-downloaded images onto a card.
  static const String offloadPath = '/offload';

  /// Offload route name.
  static const String offloadName = 'offload';

  /// Blocked-tags management path.
  static const String blockedTagsPath = '/blocked-tags';

  /// Blocked-tags management route name.
  static const String blockedTagsName = 'blocked-tags';

  /// Path of the immersive, local-first viewer over the download history.
  static const String downloadViewerPath = '/downloads/view';

  /// Download-history viewer route name.
  static const String downloadViewerName = 'download-viewer';
}
