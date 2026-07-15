import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';

void main() {
  group('shelfHeroTag', () {
    test('one id at one position on two shelves yields two distinct tags', () {
      // Browse and Favorites are both mounted in go_router's IndexedStack, so
      // a wallpaper kept in Favorites and also on the Browse grid would raise
      // "multiple heroes share the same tag" if scoped by id alone.
      expect(
        shelfHeroTag('browse?page=1', 'abc', 0),
        isNot(shelfHeroTag('favorites', 'abc', 0)),
      );
      expect(
        shelfHeroTag('download-history', 'abc', 0),
        isNot(shelfHeroTag('private-library', 'abc', 0)),
      );
    });

    test('the same shelf, id, and position stays stable across calls', () {
      expect(
        shelfHeroTag('favorites', 'abc', 3),
        shelfHeroTag('favorites', 'abc', 3),
      );
    });

    test('one id repeated at two positions on a shelf never collides', () {
      // Wallhaven's random sort can repeat a wallpaper across pages, so the
      // grid can render one id twice; the position keeps their tags apart.
      expect(
        shelfHeroTag('browse?page=1', 'abc', 4),
        isNot(shelfHeroTag('browse?page=1', 'abc', 27)),
      );
    });
  });
}
