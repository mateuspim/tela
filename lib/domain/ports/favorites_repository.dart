import 'package:tela/domain/models/wallpaper.dart';

/// The wallpapers the user kept, stored on this device only.
///
/// A pure-domain port: no package sits behind it, and Wallhaven has no idea
/// these exist — favoriting is local, unlike the account's own favorites.
///
/// Implementations store the whole [Wallpaper], not just its id, so the
/// favorites grid renders with no network at all.
abstract interface class FavoritesRepository {
  /// Every saved wallpaper, most recently saved first.
  Future<List<Wallpaper>> favorites();

  /// Whether [wallpaperId] is currently saved.
  Future<bool> isFavorite(String wallpaperId);

  /// Saves [wallpaper], replacing any earlier copy of the same id.
  Future<void> save(Wallpaper wallpaper);

  /// Drops the wallpaper with [wallpaperId]. A no-op when it was never saved.
  Future<void> forget(String wallpaperId);
}
