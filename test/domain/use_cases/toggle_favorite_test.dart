import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/use_cases/toggle_favorite.dart';

import '../../fakes/fake_favorites_repository.dart';

void main() {
  group('ToggleFavorite', () {
    test('saves a wallpaper that was not a favorite, and says so', () async {
      final FakeFavoritesRepository favorites = FakeFavoritesRepository();
      final ToggleFavorite toggle = ToggleFavorite(favorites: favorites);

      final bool isFavorite = await toggle(_wallpaper('e7jvjd'));

      expect(isFavorite, isTrue);
      expect(await favorites.favorites(), <Wallpaper>[_wallpaper('e7jvjd')]);
    });

    test('forgets a wallpaper that was already a favorite', () async {
      final FakeFavoritesRepository favorites = FakeFavoritesRepository(
        initial: <Wallpaper>[_wallpaper('e7jvjd')],
      );
      final ToggleFavorite toggle = ToggleFavorite(favorites: favorites);

      final bool isFavorite = await toggle(_wallpaper('e7jvjd'));

      expect(isFavorite, isFalse);
      expect(await favorites.favorites(), isEmpty);
      expect(favorites.saveCount, 0, reason: 'un-favoriting must not re-save');
    });

    test('toggling twice returns the wallpaper to where it started', () async {
      final FakeFavoritesRepository favorites = FakeFavoritesRepository();
      final ToggleFavorite toggle = ToggleFavorite(favorites: favorites);

      await toggle(_wallpaper('e7jvjd'));
      final bool isFavorite = await toggle(_wallpaper('e7jvjd'));

      expect(isFavorite, isFalse);
      expect(await favorites.favorites(), isEmpty);
    });

    test('leaves other favorites alone', () async {
      final FakeFavoritesRepository favorites = FakeFavoritesRepository(
        initial: <Wallpaper>[_wallpaper('keep'), _wallpaper('drop')],
      );
      final ToggleFavorite toggle = ToggleFavorite(favorites: favorites);

      await toggle(_wallpaper('drop'));

      expect(await favorites.favorites(), <Wallpaper>[_wallpaper('keep')]);
    });
  });
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
