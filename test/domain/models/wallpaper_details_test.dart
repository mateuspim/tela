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
  });
}
