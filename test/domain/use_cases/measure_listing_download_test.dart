import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/listing_download_size.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/use_cases/measure_listing_download.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_tag_blocklist_repository.dart';
import '../../fakes/fake_wallpaper_source.dart';

/// The number put in front of the user before a whole tag is committed to.
///
/// "Download everything tagged anime" and "download everything by @dude" are
/// the same gesture over a hundredfold difference in commitment, and nothing
/// else on the screen distinguishes them.
void main() {
  test('measures the whole listing from one request', () async {
    // The cost rule: measuring a 12,000-wallpaper tag must cost the same as
    // measuring a 12-wallpaper one, or the confirmation spends the rate limit
    // answering a question the user may well say no to.
    final FakeWallpaperSource source = FakeWallpaperSource(
      page: _page(count: 3, total: 12431, bytesEach: 4000000),
    );

    final ListingDownloadSize size = await _measure(source)(
      const SearchQuery(term: 'anime'),
    );

    expect(size.wallpapers, 12431);
    expect(size.isCounted, isTrue);
    expect(source.receivedQueries, hasLength(1));
    expect(source.receivedQueries.single.page, 1);
  });

  test('extrapolates the size from the first page it saw', () async {
    final FakeWallpaperSource source = FakeWallpaperSource(
      page: _page(count: 2, total: 100, bytesEach: 3000000),
    );

    final ListingDownloadSize size = await _measure(source)(
      const SearchQuery(),
    );

    expect(size.bytes, 300000000, reason: '3MB mean over 100 wallpapers');
  });

  test('a source that does not count says so rather than guessing', () async {
    // Konachan returns a bare array with no metadata at all, so its listings
    // have no size until you walk to the end. A confirmation that invented a
    // number here would be lying about the only fact it exists to state.
    final FakeWallpaperSource source = FakeWallpaperSource(
      page: _page(count: 3, total: null, bytesEach: 4000000),
    );

    final ListingDownloadSize size = await _measure(source)(
      const SearchQuery(),
    );

    expect(size.isCounted, isFalse);
    expect(size.wallpapers, isNull);
    expect(size.bytes, isNull);
  });

  test('an empty listing estimates nothing rather than zero bytes', () async {
    // "Roughly 0 bytes" is a claim about file sizes. An empty first page means
    // there was nothing to measure, which is a different statement.
    final FakeWallpaperSource source = FakeWallpaperSource(
      page: _page(count: 0, total: 0, bytesEach: 0),
    );

    final ListingDownloadSize size = await _measure(source)(
      const SearchQuery(),
    );

    expect(size.isEmpty, isTrue);
    expect(size.bytes, isNull);
  });
}

MeasureListingDownload _measure(FakeWallpaperSource source) =>
    MeasureListingDownload(
      search: SearchWallpapers(
        source: source,
        secrets: FakeSecretStore(),
        blocklist: FakeTagBlocklistRepository(),
      ),
    );

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
