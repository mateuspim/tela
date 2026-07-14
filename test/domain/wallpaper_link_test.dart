import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';

void main() {
  group('TagLink', () {
    test('searches the exact tag id, not the tag name', () {
      const TagLink link = TagLink(WallpaperTag(id: 37, name: 'nature'));

      // `+nature` would be a fuzzy text match and would return wallpapers
      // carrying a different tag that merely reads the same.
      expect(link.term, 'id:37');
    });

    test('is the same link as another link to the same tag', () {
      const TagLink one = TagLink(WallpaperTag(id: 37, name: 'nature'));
      const TagLink two = TagLink(WallpaperTag(id: 37, name: 'nature'));
      const TagLink other = TagLink(WallpaperTag(id: 38, name: 'nature'));

      expect(one, two);
      expect(one.hashCode, two.hashCode);
      expect(one, isNot(other));
    });
  });

  group('UploaderLink', () {
    test('searches Wallhaven for the uploader', () {
      expect(const UploaderLink('pym').term, '@pym');
    });

    test('is the same link as another link to the same uploader', () {
      expect(const UploaderLink('pym'), const UploaderLink('pym'));
      expect(const UploaderLink('pym'), isNot(const UploaderLink('other')));
    });

    test('is never equal to a tag link', () {
      const TagLink tag = TagLink(WallpaperTag(id: 1, name: 'pym'));

      expect(const UploaderLink('pym'), isNot(tag));
    });
  });
}
