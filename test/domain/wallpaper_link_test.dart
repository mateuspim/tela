import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';

void main() {
  // A query already narrowed by the user, to prove a link layers over it
  // rather than replacing it: purity stays, only the term or colour changes.
  const SearchQuery browsing = SearchQuery(
    term: 'sunset',
    purity: PurityFilter(<Purity>{Purity.sfw, Purity.sketchy}),
  );

  group('TagLink', () {
    test('replaces the term with the exact tag id, newest first', () {
      const TagLink link = TagLink(WallpaperTag(id: 37, name: 'nature'));

      final SearchQuery query = link.narrow(browsing);

      // `+nature` would be a fuzzy text match and would return wallpapers
      // carrying a different tag that merely reads the same.
      expect(query.term, 'id:37');
      expect(query.sorting, Sorting.dateAdded);
      // The user's purity is untouched — a follow must not widen a filter.
      expect(query.purity.purities, <Purity>{Purity.sfw, Purity.sketchy});
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
    test('replaces the term with the uploader operator', () {
      final SearchQuery query = const UploaderLink('pym').narrow(browsing);

      expect(query.term, '@pym');
      expect(query.sorting, Sorting.dateAdded);
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

  group('ColorLink', () {
    test('sets the colour and clears the term, keeping the filters', () {
      final SearchQuery query = ColorLink(WallpaperColor('#0066cc')).narrow(
        browsing,
      );

      // "More like this colour" is a colour param, not a q term: the previous
      // search text goes, the colour arrives, and the purity stays.
      expect(query.color, WallpaperColor('#0066cc'));
      expect(query.term, '');
      expect(query.sorting, Sorting.dateAdded);
      expect(query.purity.purities, <Purity>{Purity.sfw, Purity.sketchy});
    });

    test('is the same link as another link to the same colour', () {
      final ColorLink blue = ColorLink(WallpaperColor('#0066cc'));

      expect(blue, ColorLink(WallpaperColor('#0066cc')));
      expect(blue, isNot(ColorLink(WallpaperColor('#660000'))));
    });

    test('is never equal to a tag or uploader link', () {
      final ColorLink blue = ColorLink(WallpaperColor('#0066cc'));

      expect(blue, isNot(const UploaderLink('x')));
    });
  });
}
