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
}
