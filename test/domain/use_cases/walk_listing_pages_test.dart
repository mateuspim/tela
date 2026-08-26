import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';
import 'package:tela/domain/use_cases/walk_listing_pages.dart';

import '../../fakes/fake_secret_store.dart';
import '../../fakes/fake_tag_blocklist_repository.dart';
import '../../fakes/fake_wallpaper_source.dart';

/// Walking a whole listing so a tag can be downloaded without scrolling it.
///
/// The owner's ask (2026-08-25): *"if i still didnt select all images from a
/// user or tag, i can select all from user/tag to download so i dont need to
/// scroll all the way down"*. The thing under test is the half that makes it
/// affordable — pages are handed over and forgotten, never gathered.
void main() {
  test('hands over every page in order and reports the count', () async {
    final FakeWallpaperSource source = FakeWallpaperSource(
      pagesByNumber: <int, WallpaperPage>{
        1: _page(<String>['a', 'b'], currentPage: 1, lastPage: 3),
        2: _page(<String>['c', 'd'], currentPage: 2, lastPage: 3),
        3: _page(<String>['e'], currentPage: 3, lastPage: 3),
      },
    );
    final List<String> seen = <String>[];

    final int walked = await _walk(source)(
      const SearchQuery(term: 'forest'),
      onPage: (List<Wallpaper> page) async {
        seen.addAll(page.map((Wallpaper w) => w.id));
      },
    );

    expect(seen, <String>['a', 'b', 'c', 'd', 'e']);
    expect(walked, 5);
  });

  test('stops at the last page instead of asking past the end', () async {
    // `hasMore: false` is the whole stop condition. Requesting page 4 of a
    // three-page listing spends a request off a 45/min budget to be told
    // nothing.
    final FakeWallpaperSource source = FakeWallpaperSource(
      pagesByNumber: <int, WallpaperPage>{
        1: _page(<String>['a'], currentPage: 1, lastPage: 2),
        2: _page(<String>['b'], currentPage: 2, lastPage: 2),
      },
    );

    await _walk(source)(const SearchQuery(), onPage: _ignore);

    expect(source.receivedQueries.map((SearchQuery q) => q.page), <int>[1, 2]);
  });

  test('a cancel lands within a page, not at the end of the listing', () async {
    // A user who stops a 12,000-wallpaper walk must not wait out the rest of
    // it. Cancelling after the first hand-over must stop the next request.
    final FakeWallpaperSource source = FakeWallpaperSource(
      pagesByNumber: <int, WallpaperPage>{
        for (int page = 1; page <= 5; page++)
          page: _page(<String>['w$page'], currentPage: page, lastPage: 5),
      },
    );
    bool stopped = false;

    final int walked = await _walk(source)(
      const SearchQuery(),
      onPage: (List<Wallpaper> _) async => stopped = true,
      isCancelled: () => stopped,
    );

    expect(walked, 1, reason: 'the page already handed over still counts');
    expect(source.receivedQueries, hasLength(1));
  });

  test('a source that never says stop is cut off by the page cap', () async {
    // The runaway guard. `hasMore` comes from the source, so a bug or a proxy
    // answering true forever would page until the rate limit died and then
    // keep going.
    final FakeWallpaperSource source = FakeWallpaperSource(
      pageFor: (SearchQuery query) =>
          _page(<String>['w'], currentPage: query.page, lastPage: 9999),
    );

    final int walked = await _walk(source)(
      const SearchQuery(),
      onPage: _ignore,
      maxPages: 4,
    );

    expect(walked, 4);
    expect(source.receivedQueries, hasLength(4));
  });

  test('resumes after a page the caller already holds', () async {
    // The confirmation has to fetch page 1 to know how big the listing is.
    // Re-fetching it spends a second request off a 45/min budget to learn what
    // is already in hand — and on a random listing re-rolls the shuffle.
    final FakeWallpaperSource source = FakeWallpaperSource(
      pagesByNumber: <int, WallpaperPage>{
        2: _page(<String>['c'], currentPage: 2, lastPage: 2),
      },
    );
    final WallpaperPage first = _page(
      <String>['a', 'b'],
      currentPage: 1,
      lastPage: 2,
    );
    final List<String> seen = <String>[];

    final int walked = await _walk(source)(
      const SearchQuery(),
      after: first,
      onPage: (List<Wallpaper> page) async {
        seen.addAll(page.map((Wallpaper w) => w.id));
      },
    );

    expect(seen, <String>['c'], reason: "page 1 was the caller's to enqueue");
    expect(walked, 1);
    expect(source.receivedQueries.single.page, 2);
  });

  test('a listing whose only page the caller holds asks for nothing', () async {
    // `hasMore: false` on the page already in hand means the walk has no work.
    // Asking for page 2 of a one-page listing burns a request to be told so.
    final FakeWallpaperSource source = FakeWallpaperSource();

    final int walked = await _walk(source)(
      const SearchQuery(),
      after: _page(<String>['a'], currentPage: 1, lastPage: 1),
      onPage: _ignore,
    );

    expect(walked, 0);
    expect(source.receivedQueries, isEmpty);
  });

  test('carries the shuffle seed so a random listing cannot repeat', () async {
    // The same trap `nextPageAfter` exists for: a `random` listing re-rolls
    // without its seed, so the walk would hand over wallpapers it had already
    // queued and skip others entirely.
    final FakeWallpaperSource source = FakeWallpaperSource(
      pagesByNumber: <int, WallpaperPage>{
        1: _page(<String>['a'], currentPage: 1, lastPage: 2, seed: 'abc123'),
        2: _page(<String>['b'], currentPage: 2, lastPage: 2, seed: 'abc123'),
      },
    );

    await _walk(source)(
      const SearchQuery(sorting: Sorting.random),
      onPage: _ignore,
    );

    expect(source.receivedQueries.last.seed, 'abc123');
  });

  test('a failure mid-walk leaves the pages already handed over', () async {
    // The queue is the authority on what happens to a queued wallpaper. A walk
    // that unwound its own hand-overs would delete work the queue had accepted.
    final FakeWallpaperSource source = FakeWallpaperSource(
      pageFor: (SearchQuery query) => query.page == 1
          ? _page(<String>['a', 'b'], currentPage: 1, lastPage: 3)
          : throw const NetworkFailure('lost the connection'),
    );
    final List<String> seen = <String>[];

    await expectLater(
      _walk(source)(
        const SearchQuery(),
        onPage: (List<Wallpaper> page) async {
          seen.addAll(page.map((Wallpaper w) => w.id));
        },
      ),
      throwsA(isA<NetworkFailure>()),
    );

    expect(seen, <String>['a', 'b']);
  });
}

WalkListingPages _walk(FakeWallpaperSource source) => WalkListingPages(
  search: SearchWallpapers(
    source: source,
    secrets: FakeSecretStore(),
    blocklist: FakeTagBlocklistRepository(),
  ),
);

Future<void> _ignore(List<Wallpaper> _) async {}

WallpaperPage _page(
  List<String> ids, {
  required int currentPage,
  required int lastPage,
  String? seed,
}) => WallpaperPage(
  wallpapers: <Wallpaper>[for (final String id in ids) _wallpaper(id)],
  hasMore: currentPage < lastPage,
  currentPage: currentPage,
  lastPage: lastPage,
  seed: seed,
);

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
