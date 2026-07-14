import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/favorites_repository.dart';

/// Saves a wallpaper to the favorites, or drops it if it is already there.
///
/// ```dart
/// final bool isNowFavorite = await toggleFavorite(wallpaper);
/// ```
class ToggleFavorite {
  /// Creates the use case over the favorites [FavoritesRepository].
  const ToggleFavorite({required FavoritesRepository favorites})
    : _favorites = favorites;

  final FavoritesRepository _favorites;

  /// Flips [wallpaper]'s favorite state and returns the state it landed in.
  ///
  /// Returns the new state rather than void so the caller can render the heart
  /// from the answer instead of re-reading the store to find out what it did.
  Future<bool> call(Wallpaper wallpaper) async {
    if (await _favorites.isFavorite(wallpaper.id)) {
      await _favorites.forget(wallpaper.id);
      return false;
    }
    await _favorites.save(wallpaper);
    return true;
  }
}
