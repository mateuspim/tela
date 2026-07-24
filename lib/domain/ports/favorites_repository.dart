import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

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

  /// Whether [ref] is currently saved.
  Future<bool> isFavorite(WallpaperRef ref);

  /// Saves [wallpaper], replacing any earlier copy of the same [Wallpaper.ref].
  Future<void> save(Wallpaper wallpaper);

  /// Drops the wallpaper [ref] names. A no-op when it was never saved.
  Future<void> forget(WallpaperRef ref);
}
