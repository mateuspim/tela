import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/listing_download_size.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// The number put in front of the user before a whole tag is committed to.
///
/// "Download everything tagged anime" and "download everything by @dude" are
/// the same gesture over a hundredfold difference in commitment, and nothing
/// else on the screen distinguishes them.
void main() {
  test('takes the count from the page the caller already fetched', () {
    final ListingDownloadSize size = ListingDownloadSize.of(
      _page(count: 3, total: 12431, bytesEach: 4000000),
    );

    expect(size.wallpapers, 12431);
    expect(size.isCounted, isTrue);
  });

  test('extrapolates the size from the sample it was given', () {
    final ListingDownloadSize size = ListingDownloadSize.of(
      _page(count: 2, total: 100, bytesEach: 3000000),
    );

    expect(size.bytes, 300000000, reason: '3MB mean over 100 wallpapers');
  });

  test('a source that does not count says so rather than guessing', () {
    // Konachan returns a bare array with no metadata at all, so its listings
    // have no size until you walk to the end. A confirmation that invented a
    // number here would be lying about the only fact it exists to state.
    final ListingDownloadSize size = ListingDownloadSize.of(
      _page(count: 3, total: null, bytesEach: 4000000),
    );

    expect(size.isCounted, isFalse);
    expect(size.wallpapers, isNull);
    expect(size.bytes, isNull);
  });

  test('an empty listing estimates nothing rather than zero bytes', () {
    // "Roughly 0 bytes" is a claim about file sizes. An empty first page means
    // there was nothing to measure, which is a different statement.
    final ListingDownloadSize size = ListingDownloadSize.of(
      _page(count: 0, total: 0, bytesEach: 0),
    );

    expect(size.isEmpty, isTrue);
    expect(size.bytes, isNull);
  });
}

WallpaperPage _page({
  required int count,
  required int? total,
  required int bytesEach,
}) => WallpaperPage(
  wallpapers: <Wallpaper>[
    for (int i = 0; i < count; i++) _wallpaper('w$i', bytesEach),
  ],
  hasMore: false,
  currentPage: 1,
  lastPage: 1,
  total: total,
);

Wallpaper _wallpaper(String id, int bytes) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: bytes,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
