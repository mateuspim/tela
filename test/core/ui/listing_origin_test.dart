import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/listing_origin.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';

/// Which listing a download is being taken from, and what it is called.
///
/// The two halves are separate on purpose. A Browse search says what it is in
/// its own query; a followed tag searches on `id:37` and cannot, so the screen
/// that followed the link hands the word over. Both arrive here.
void main() {
  group('the folder a listing offers', () {
    testWidgets('is the explicit one when the listing carries a name', (
      WidgetTester tester,
    ) async {
      // The name wins over anything readable from the query, which for a
      // followed tag is the `id:37` operator and nothing useful.
      final TagFolder? folder = await _folderUnder(
        tester,
        ListingOrigin(
          filters: const SearchQuery(term: 'id:37'),
          folder: TagFolder('white minimalist'),
          child: const _Probe(),
        ),
      );

      expect(folder, TagFolder('white minimalist'));
    });

    testWidgets('falls back to what the query itself searches for', (
      WidgetTester tester,
    ) async {
      // Browse. Nothing hands a name over here because the query is the name.
      final TagFolder? folder = await _folderUnder(
        tester,
        const ListingOrigin(
          filters: SearchQuery(tags: <SearchTag>[SearchTag('cyberpunk')]),
          folder: null,
          child: _Probe(),
        ),
      );

      expect(folder, TagFolder('cyberpunk'));
    });

    testWidgets('is nothing at all off a listing', (
      WidgetTester tester,
    ) async {
      // Favorites, the download history, a deep link. These used to inherit
      // Browse's search term through the provider, which described none of
      // them; suggesting nothing is the honest answer.
      final TagFolder? folder = await _folderUnder(tester, const _Probe());

      expect(folder, isNull);
    });
  });

  group('the folder a link names', () {
    test('a tag is its name, never the id it searches on', () {
      // `TagLink.narrow` sets the term to `id:37`, which sanitizes into a
      // perfectly legal folder called `id 37`. That is why the link is asked
      // rather than the query it produces.
      const TagLink link = TagLink(WallpaperTag(id: 37, name: 'nature'));

      expect(link.folderName, TagFolder('nature'));
      final String searched = link.narrow(const SearchQuery()).term;
      expect(TagFolder.sanitize(searched)?.name, 'id 37');
    });

    test('an uploader is their username', () {
      expect(const UploaderLink('pym').folderName, TagFolder('pym'));
    });

    test('a colour is nothing, because it has no word', () {
      // The screen titles a colour listing with a swatch. There is nothing to
      // call a directory, and inventing one would file downloads under a name
      // the user never saw.
      expect(ColorLink(WallpaperColor('#660000')).folderName, isNull);
    });

    test('a tag whose name cannot be a folder names none', () {
      // Konachan carries emoticon tags. `TagFolder.sanitize` drops what leaves
      // no letter or digit rather than filing under `_`.
      const TagLink link = TagLink(WallpaperTag(id: 9, name: '>_<'));

      expect(link.folderName, isNull);
    });
  });
}

/// Mounts [tree] and answers what a widget under it would be offered.
Future<TagFolder?> _folderUnder(WidgetTester tester, Widget tree) async {
  await tester.pumpWidget(MaterialApp(home: tree));
  return ListingOrigin.folderOf(tester.element(find.byType(_Probe)));
}

/// A leaf to read the scope from — the scope answers a `BuildContext`, so a
/// test needs one that is genuinely underneath it.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
