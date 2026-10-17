import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/listing_download_walk.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/batch_routing.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/use_cases/drain_download_queue.dart';

import '../fakes/fake_download_queue.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// Downloading a whole tag or uploader without scrolling to the end of it.
///
/// The owner's ask (2026-08-25). The thing worth pinning is the promise: that
/// wallpapers **nobody has scrolled to** reach the queue, which is exactly what
/// the selection path could never do — a ticked id is resolved back against the
/// loaded shelf, so a tick for an unfetched page is dropped in silence.
void main() {
  test('queues wallpapers from pages nobody scrolled to', () async {
    final FakeWallpaperSource source = _source(pages: 3, perPage: 2);
    final FakeDownloadQueue queue = FakeDownloadQueue();
    final ProviderContainer container = _container(source, queue);

    final int queued = await container
        .read(listingDownloadWalkProvider.notifier)
        .start(
          query: const SearchQuery(term: 'forest'),
          first: _page(<String>['p1a', 'p1b'], currentPage: 1, lastPage: 3),
          listing: '#forest',
        );

    expect(queued, 6, reason: 'page 1 in hand plus pages 2 and 3 walked');
    final List<QueuedDownload> entries = await queue.entries();
    expect(entries.map((QueuedDownload e) => e.ref.id), <String>[
      'p1a',
      'p1b',
      'p2a',
      'p2b',
      'p3a',
      'p3b',
    ]);
  });

  // Owner, 2026-10-16: a listing that may turn up explicit wallpapers lands
  // whole under the explicit rules, rather than split across gallery and card.
  test('an explicit routing queues every page as explicit', () async {
    final FakeWallpaperSource source = _source(pages: 2, perPage: 1);
    final FakeDownloadQueue queue = FakeDownloadQueue();
    final ProviderContainer container = _container(source, queue);

    await container
        .read(listingDownloadWalkProvider.notifier)
        .start(
          query: const SearchQuery(),
          first: _page(<String>['p1a'], currentPage: 1, lastPage: 2),
          listing: '#x',
          routing: const BatchRouting(<Purity>{Purity.sfw, Purity.nsfw}),
        );

    final List<QueuedDownload> entries = await queue.entries();
    expect(entries, hasLength(2));
    expect(entries.every((QueuedDownload e) => e.wallpaper.isNsfw), isTrue);
  });

  test('does not re-fetch the page the caller already holds', () async {
    // The confirmation had to fetch page 1 to size the listing. Fetching it
    // again spends a request off a 45/min budget to learn what is in hand.
    final FakeWallpaperSource source = _source(pages: 2, perPage: 1);
    final ProviderContainer container = _container(source, FakeDownloadQueue());

    await container
        .read(listingDownloadWalkProvider.notifier)
        .start(
          query: const SearchQuery(),
          first: _page(<String>['p1a'], currentPage: 1, lastPage: 2),
          listing: '#x',
        );

    expect(source.receivedQueries.map((SearchQuery q) => q.page), <int>[2]);
  });

  test('a stop leaves what was queued and asks for no more pages', () async {
    // Undoing would delete work the queue has accepted and may already have
    // downloaded. The queue's own screen is where entries are removed.
    final FakeWallpaperSource source = _source(pages: 6, perPage: 1);
    final FakeDownloadQueue queue = FakeDownloadQueue();
    final ProviderContainer container = _container(source, queue);
    final ListingDownloadWalk walk = container.read(
      listingDownloadWalkProvider.notifier,
    );

    final Future<int> walking = walk.start(
      query: const SearchQuery(),
      first: _page(<String>['p1a'], currentPage: 1, lastPage: 6),
      listing: '#x',
    );
    walk.stop();
    await walking;

    expect(await queue.entries(), isNotEmpty);
    expect(
      source.receivedQueries.length,
      lessThan(5),
      reason: 'a stop must not wait out the rest of the listing',
    );
  });

  test('refuses a second walk while one is running', () async {
    // Two walks interleave through the same 45/min limiter, so each takes
    // twice as long — and the progress line could only describe one of them.
    final FakeWallpaperSource source = _source(pages: 3, perPage: 1);
    final FakeDownloadQueue queue = FakeDownloadQueue();
    final ProviderContainer container = _container(source, queue);
    final ListingDownloadWalk walk = container.read(
      listingDownloadWalkProvider.notifier,
    );

    final Future<int> first = walk.start(
      query: const SearchQuery(),
      first: _page(<String>['p1a'], currentPage: 1, lastPage: 3),
      listing: '#first',
    );
    final int second = await walk.start(
      query: const SearchQuery(term: 'other'),
      first: _page(<String>['q1a'], currentPage: 1, lastPage: 3),
      listing: '#second',
    );
    await first;

    expect(second, 0);
    final List<QueuedDownload> entries = await queue.entries();
    expect(
      entries.map((QueuedDownload e) => e.ref.id),
      isNot(contains('q1a')),
      reason: 'the refused walk must queue nothing at all',
    );
  });

  test('reports what the queue accepted, not what it walked past', () async {
    // The queue is idempotent per wallpaper. Re-running a listing already
    // waiting adds nothing, and saying "queued 6" over a queue that did not
    // grow is the same lie the old aggregate tally was.
    final FakeWallpaperSource source = _source(pages: 2, perPage: 2);
    final FakeDownloadQueue queue = FakeDownloadQueue();
    final ProviderContainer container = _container(source, queue);
    final WallpaperPage first = _page(
      <String>['p1a', 'p1b'],
      currentPage: 1,
      lastPage: 2,
    );

    await container
        .read(listingDownloadWalkProvider.notifier)
        .start(query: const SearchQuery(), first: first, listing: '#x');
    final int again = await container
        .read(listingDownloadWalkProvider.notifier)
        .start(query: const SearchQuery(), first: first, listing: '#x');

    expect(again, 0);
  });
}

/// A source answering [pages] pages of [perPage] wallpapers, ids `p{page}a..`.
FakeWallpaperSource _source({required int pages, required int perPage}) {
  return FakeWallpaperSource(
    pageFor: (SearchQuery query) => _page(
      <String>[
        for (int i = 0; i < perPage; i++) _id(query, i),
      ],
      currentPage: query.page,
      lastPage: pages,
    ),
  );
}

/// `p2a` for page 2's first wallpaper — and `q…` for the listing a refused
/// second walk would have fetched, so the two can never be confused.
String _id(SearchQuery query, int index) {
  final String listing = query.term == 'other' ? 'q' : 'p';
  return '$listing${query.page}${String.fromCharCode(97 + index)}';
}

ProviderContainer _container(
  FakeWallpaperSource source,
  FakeDownloadQueue queue,
) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      wallhavenSourceProvider.overrideWithValue(source),
      secretStoreProvider.overrideWithValue(FakeSecretStore()),
      tagBlocklistRepositoryProvider.overrideWithValue(
        FakeTagBlocklistRepository(),
      ),
      downloadQueueProvider.overrideWithValue(queue),
      imageStoreProvider.overrideWithValue(FakeImageStore()),
      // Never completes: the walk is under test, not the draining that follows
      // it, and a drain that ran would empty the queue mid-assertion.
      drainDownloadQueueProvider.overrideWithValue(
        DrainDownloadQueue(
          queue: queue,
          perform: (Wallpaper wallpaper, {StorageTier? tier, TagFolder? tag}) =>
              Completer<void>().future,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

WallpaperPage _page(
  List<String> ids, {
  required int currentPage,
  required int lastPage,
}) => WallpaperPage(
  wallpapers: <Wallpaper>[for (final String id in ids) _wallpaper(id)],
  hasMore: currentPage < lastPage,
  currentPage: currentPage,
  lastPage: lastPage,
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
