import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/favorites_repository.dart';

/// Every favorited wallpaper, newest first — the favorites grid's whole source.
///
/// Reads from SQLite, never from Wallhaven, so it resolves offline.
final FutureProvider<List<Wallpaper>> favoritesProvider =
    FutureProvider<List<Wallpaper>>((Ref ref) {
      final FavoritesRepository favorites = ref.watch(
        favoritesRepositoryProvider,
      );
      return favorites.favorites();
    });

/// Whether one wallpaper is favorited — what the detail screen's heart renders.
final FutureProviderFamily<bool, WallpaperRef> isFavoriteProvider =
    FutureProvider.family<bool, WallpaperRef>((
      Ref ref,
      WallpaperRef wallpaper,
    ) {
      final FavoritesRepository favorites = ref.watch(
        favoritesRepositoryProvider,
      );
      return favorites.isFavorite(wallpaper);
    });

/// Re-reads both views of the favorites after a write.
///
/// Toggling the heart on the detail screen must also change the grid behind it;
/// invalidating one provider and not the other is how a removed favorite stays
/// on screen until the next cold start.
void refreshFavorites(WidgetRef ref, WallpaperRef wallpaper) {
  ref
    ..invalidate(favoritesProvider)
    ..invalidate(isFavoriteProvider(wallpaper));
}
