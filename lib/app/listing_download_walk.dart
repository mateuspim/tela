import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/batch_routing.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// How far a whole-listing download has got, or null when none is running.
///
/// [queued] is what the queue actually accepted, not what was walked past: the
/// queue is idempotent per wallpaper, so re-running a listing whose wallpapers
/// are already waiting adds nothing and must not claim to have.
class ListingWalkProgress {
  /// Creates a progress reading.
  const ListingWalkProgress({
    required this.listing,
    required this.queued,
    required this.isRunning,
  });

  /// What the user asked for, as the screen names it — `#anime`, `@dude`.
  final String listing;

  /// How many wallpapers the queue has newly accepted so far.
  final int queued;

  /// Whether pages are still being fetched.
  final bool isRunning;
}

/// The one in-flight whole-listing download.
///
/// **A notifier rather than screen state, because the walk outlives the
/// screen.** A 500-page listing takes minutes at Wallhaven's 45 requests a
/// minute, and a user who starts one and taps Back has not changed their mind
/// — a walk owned by the pushed listing would be torn down with it and queue
/// half a tag. Non-autoDispose for the same reason the download queue is.
///
/// Only one runs at a time. A second `start` while one is running is refused
/// rather than queued: two walks would interleave their requests through the
/// same 45-per-minute limiter and each take twice as long, and the progress
/// line could only describe one of them.
final NotifierProvider<ListingDownloadWalk, ListingWalkProgress?>
listingDownloadWalkProvider =
    NotifierProvider<ListingDownloadWalk, ListingWalkProgress?>(
      ListingDownloadWalk.new,
    );

/// Walks a listing and feeds every page into the download queue.
class ListingDownloadWalk extends Notifier<ListingWalkProgress?> {
  bool _stopped = false;

  @override
  ListingWalkProgress? build() => null;

  /// Whether a walk is already running, and so a second one must be refused.
  bool get isRunning => state?.isRunning ?? false;

  /// Stops the walk after the page in flight. Nothing already queued is undone.
  ///
  /// Undoing would delete work the queue has accepted and may already have
  /// downloaded — the queue's own screen is where a user removes entries, with
  /// the file's fate reported per item.
  void stop() => _stopped = true;

  /// Queues [first] and then every remaining page of [query].
  ///
  /// [first] is the page the confirmation already fetched to size the listing;
  /// re-fetching it here would spend a request to learn what is in hand, and on
  /// a `random` listing would re-roll the shuffle.
  ///
  /// [routing] is applied to every page, so a listing that may turn up an
  /// explicit wallpaper queues each one as explicit — see [BatchRouting].
  ///
  /// Returns how many wallpapers the queue newly accepted.
  Future<int> start({
    required SearchQuery query,
    required WallpaperPage first,
    required String listing,
    StorageTier? tier,
    TagFolder? tag,
    BatchRouting routing = const BatchRouting(<Purity>{}),
  }) async {
    if (isRunning) return 0;
    _stopped = false;
    state = ListingWalkProgress(listing: listing, queued: 0, isRunning: true);
    try {
      await _queue(routing.apply(first.wallpapers), tier: tier, tag: tag);
      await ref
          .read(walkListingPagesProvider)
          .call(
            query,
            after: first,
            isCancelled: () => _stopped,
            onPage: (List<Wallpaper> page) =>
                _queue(routing.apply(page), tier: tier, tag: tag),
          );
    } finally {
      state = ListingWalkProgress(
        listing: listing,
        queued: state?.queued ?? 0,
        isRunning: false,
      );
    }
    return state?.queued ?? 0;
  }

  /// Commits one page and republishes the running total.
  Future<void> _queue(
    List<Wallpaper> page, {
    required StorageTier? tier,
    required TagFolder? tag,
  }) async {
    final int accepted = await ref
        .read(downloadQueueControllerProvider.notifier)
        .enqueue(page, tier: tier, tag: tag);
    final ListingWalkProgress? running = state;
    if (running == null) return;
    state = ListingWalkProgress(
      listing: running.listing,
      queued: running.queued + accepted,
      isRunning: running.isRunning,
    );
  }
}
