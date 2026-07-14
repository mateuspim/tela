import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/wallpaper.dart';
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
final FutureProviderFamily<bool, String> isFavoriteProvider =
    FutureProvider.family<bool, String>((Ref ref, String wallpaperId) {
      final FavoritesRepository favorites = ref.watch(
        favoritesRepositoryProvider,
      );
      return favorites.isFavorite(wallpaperId);
    });

/// Re-reads both views of the favorites after a write.
///
/// Toggling the heart on the detail screen must also change the grid behind it;
/// invalidating one provider and not the other is how a removed favorite stays
/// on screen until the next cold start.
void refreshFavorites(WidgetRef ref, String wallpaperId) {
  ref
    ..invalidate(favoritesProvider)
    ..invalidate(isFavoriteProvider(wallpaperId));
}
