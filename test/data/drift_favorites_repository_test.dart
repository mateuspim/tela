import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/favorites/drift_favorites_repository.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

void main() {
  late TelaDatabase db;
  late DriftFavoritesRepository favorites;
  late DateTime clock;

  setUp(() {
    db = TelaDatabase(NativeDatabase.memory());
    clock = DateTime.utc(2026);
    // A hand-cranked clock, so save order is pinned without sleeping between
    // writes — two saves in the same millisecond would order arbitrarily.
    favorites = DriftFavoritesRepository(
      db,
      now: () => clock = clock.add(const Duration(minutes: 1)),
    );
  });

  tearDown(() => db.close());

  group('DriftFavoritesRepository', () {
    test('has no favorites before anything is saved', () async {
      expect(await favorites.favorites(), isEmpty);
      expect(await favorites.isFavorite(_ref('e7jvjd')), isFalse);
    });

    test('round-trips every field a saved wallpaper needs', () async {
      final Wallpaper saved = _wallpaper(
        'e7jvjd',
        colors: const <String>['#660000', '#abbcda'],
      );

      await favorites.save(saved);

      final List<Wallpaper> loaded = await favorites.favorites();
      expect(loaded, <Wallpaper>[saved]);
      // Wallpaper's == is id-only, so assert the fields that let the grid draw
      // and the apply action run with no network.
      expect(loaded.single.fullImageUrl, saved.fullImageUrl);
      expect(loaded.single.thumbOriginalUrl, saved.thumbOriginalUrl);
      expect(loaded.single.resolution, const Resolution(1080, 2400));
      expect(loaded.single.fileSizeBytes, 1024);
      expect(loaded.single.purity, Purity.sfw);
      expect(loaded.single.category, Category.general);
      expect(loaded.single.colors, <String>['#660000', '#abbcda']);
    });

    test('reads a wallpaper saved with no colors as no colors', () async {
      await favorites.save(_wallpaper('e7jvjd'));

      expect((await favorites.favorites()).single.colors, isEmpty);
    });

    test('lists the most recently saved wallpaper first', () async {
      await favorites.save(_wallpaper('older'));
      await favorites.save(_wallpaper('newer'));

      final List<Wallpaper> loaded = await favorites.favorites();

      expect(loaded.map((Wallpaper w) => w.id), <String>['newer', 'older']);
    });

    test('saving the same wallpaper twice overwrites, not appends', () async {
      await favorites.save(_wallpaper('e7jvjd'));
      await favorites.save(_wallpaper('e7jvjd'));

      expect(await favorites.favorites(), hasLength(1));
    });

    test('forgets a saved wallpaper', () async {
      await favorites.save(_wallpaper('e7jvjd'));

      await favorites.forget(_ref('e7jvjd'));

      expect(await favorites.isFavorite(_ref('e7jvjd')), isFalse);
      expect(await favorites.favorites(), isEmpty);
    });

    test('forgetting a wallpaper that was never saved is a no-op', () async {
      await favorites.forget(_ref('never-there'));

      expect(await favorites.favorites(), isEmpty);
    });

    test('an nsfw favorite survives the round trip as nsfw', () async {
      await favorites.save(_wallpaper('explicit', purity: Purity.nsfw));

      expect((await favorites.favorites()).single.purity, Purity.nsfw);
    });

    test('reads an unrecognised stored purity as nsfw, never as sfw', () async {
      // A corrupt purity read as sfw is the one mistake that could get an
      // explicit image MediaStore-indexed. This fallback fails closed.
      await favorites.save(_wallpaper('e7jvjd'));
      await db
          .update(db.favoriteWallpapers)
          .write(const FavoriteWallpapersCompanion(purity: Value<String>('?')));

      expect((await favorites.favorites()).single.purity, Purity.nsfw);
    });

    test('reads an unrecognised stored category as no category', () async {
      await favorites.save(_wallpaper('e7jvjd'));
      await db
          .update(db.favoriteWallpapers)
          .write(
            const FavoriteWallpapersCompanion(category: Value<String>('memes')),
          );

      // Null, not a guess: filing it under General would be tela claiming a
      // classification the row does not support.
      expect((await favorites.favorites()).single.category, null);
    });
  });
}

Wallpaper _wallpaper(
  String id, {
  Purity purity = Purity.sfw,
  List<String> colors = const <String>[],
}) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: purity,
  category: Category.general,
  colors: colors,
);

WallpaperRef _ref(String id) => WallpaperRef(SourceId.wallhaven, id);
