import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

void main() {
  group('WallpaperPage', () {
    test('a source that counts its pages can say how many there are', () {
      final WallpaperPage page = _page(currentPage: 2, lastPage: 37);

      expect(page.hasMore, isTrue);
      expect(page.lastPage, 37);
    });

    test('a source with no page count still answers hasMore', () {
      // The Moebooru family returns a bare JSON array with no metadata: you
      // learn you are at the end by receiving a short page (PLAN §18.1). So
      // `hasMore` is the stored primitive and `lastPage` is the extra.
      final WallpaperPage page = _page(currentPage: 4, hasMore: true);

      expect(page.hasMore, isTrue);
      expect(
        page.lastPage,
        null,
        reason: 'null means "this source does not count pages", not "no more"',
      );
    });

    test('the end of an uncounted listing is a short page, not a number', () {
      final WallpaperPage page = _page(
        currentPage: 5,
        hasMore: false,
        count: 3,
      );

      expect(page.hasMore, isFalse);
      expect(page.lastPage, null);
      expect(page.wallpapers, hasLength(3));
    });
  });
}

WallpaperPage _page({
  required int currentPage,
  int? lastPage,
  bool? hasMore,
  int count = 24,
}) {
  return WallpaperPage(
    wallpapers: <Wallpaper>[
      for (int i = 0; i < count; i++) _wallpaper('w$i'),
    ],
    currentPage: currentPage,
    hasMore: hasMore ?? (lastPage != null && currentPage < lastPage),
    lastPage: lastPage,
  );
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
