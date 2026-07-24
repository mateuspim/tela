import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/wallpaper_details.dart';

void main() {
  group('WallpaperTag equality', () {
    test('is the same tag as another tag with the same id', () {
      const WallpaperTag one = WallpaperTag(id: 37, name: 'nature');
      const WallpaperTag renamed = WallpaperTag(id: 37, name: 'Nature');

      // Wallhaven can rename a tag without changing its id — the blocklist and
      // the `id:{n}` operator both key on the id, so equality must too.
      expect(one, renamed);
      expect(one.hashCode, renamed.hashCode);
    });

    test('is a different tag from one with a different id', () {
      const WallpaperTag one = WallpaperTag(id: 37, name: 'nature');
      const WallpaperTag other = WallpaperTag(id: 38, name: 'nature');

      expect(one, isNot(other));
    });

    test('falls back to the name where the source issues no ids', () {
      // A booru's tag names *are* the identifier, and fetching an id per tag
      // costs a request per tag for nothing (PLAN §18.4). Two id-less tags
      // reading the same are therefore the same constraint.
      const WallpaperTag named = WallpaperTag(name: 'landscape');
      const WallpaperTag same = WallpaperTag(name: 'landscape');
      const WallpaperTag different = WallpaperTag(name: 'portrait');

      expect(named, same);
      expect(named.hashCode, same.hashCode);
      expect(named, isNot(different));
    });

    test(
      'an id-less tag is compared by name even against an identified one',
      () {
        // The mixed case can only happen across sources, and name is the only
        // thing the two have in common — better than calling them equal.
        const WallpaperTag identified = WallpaperTag(id: 37, name: 'nature');

        expect(identified, const WallpaperTag(name: 'nature'));
        expect(identified, isNot(const WallpaperTag(name: 'forest')));
      },
    );
  });
}
