import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/selectable_wallpaper_shelf.dart';
import 'package:tela/app/wallpaper_batch_actions.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/tile_density_scope.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';
import 'package:tela/features/browse/gallery_paging_bridge.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/browse/wallpaper_wall_navigation.dart';
import 'package:tela/features/browse/wallpaper_wall_status.dart';
import 'package:tela/features/detail/wallpaper_gallery_session.dart';
import 'package:tela/features/settings/blocked_tags_providers.dart';

/// An infinite wall of wallpapers for one [query], in justified rows.
///
/// Owns its paging state, so each browse tab scrolls independently and keeps
/// its position when you switch away and back.
class WallpaperGrid extends ConsumerStatefulWidget {
  /// Creates a grid showing results for [query].
  const WallpaperGrid({
    required this.query,
    this.galleryIdentity = 'browse',
    super.key,
  });

  /// The listing to show. Page number is managed by the grid, not the caller.
  final SearchQuery query;

  /// Stable shelf kind used to distinguish Browse from linked listings.
  final String galleryIdentity;

  @override
  ConsumerState<WallpaperGrid> createState() => _WallpaperGridState();
}

class _WallpaperGridState extends ConsumerState<WallpaperGrid> {
  late final PagingController<int, Wallpaper> _paging;
  late final GalleryPagingBridge _bridge;

  /// The most recent page, kept so the next fetch can inherit its shuffle seed.
  WallpaperPage? _lastPage;

  /// The wall's own scroll position, read to tell an under-filled shelf from a
  /// scrollable one. See [_topUpIfUnderfilled].
  final ScrollController _scroll = ScrollController();

  /// Which listing [_lastPage] is allowed to describe.
  ///
  /// Bumped by [_retry], so a fetch that was superseded while in flight cannot
  /// write its page back over the one that replaced it. [PagingController]
  /// already discards a superseded fetch's *items* — it compares the operation
  /// it started with against the current one — but [_fetchPage] mutates
  /// [_lastPage] before the controller ever gets to make that call, and
  /// [_nextPageKey] answers `null` (meaning "no next page, ever") for a
  /// [_lastPage] that says `hasMore: false`. A page from the query the user
  /// just left could otherwise end the new listing at page one.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _paging = PagingController<int, Wallpaper>(
      getNextPageKey: _nextPageKey,
      fetchPage: _fetchPage,
    );
    _bridge = GalleryPagingBridge(_paging);
    // The opening fetch is ours to make. `PagedLayoutBuilder` used to schedule
    // it as a side effect of its first build, and nothing else ever did — with
    // the wall now laid out by hand, a grid that did not ask here would sit on
    // an empty listing forever, reporting "no results" for a search it never
    // ran. Same reasoning as [_retry]: asking directly does not depend on any
    // build-timing window.
    _paging.fetchNextPage();
  }

  /// Reloads from page 1 when the term or the filters change.
  ///
  /// The paging controller caches pages against the *old* query, so without
  /// this a new filter would leave the previous listing on screen and only take
  /// effect on the next scroll — which reads as the filter having been ignored.
  @override
  void didUpdateWidget(WallpaperGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query) _retry();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _paging.dispose();
    super.dispose();
  }

  /// Stops paging at Wallhaven's last page instead of requesting past the end.
  int? _nextPageKey(PagingState<int, Wallpaper> state) {
    final WallpaperPage? last = _lastPage;
    if (last != null && !last.hasMore) return null;
    return state.nextIntPageKey;
  }

  Future<List<Wallpaper>> _fetchPage(int pageKey) async {
    final int generation = _generation;
    final WallpaperPage page = await _requestPage(pageKey);
    if (generation == _generation) _lastPage = page;
    return page.wallpapers;
  }

  /// Delegates to the use case rather than building the next query here, so the
  /// `random` seed is carried by the one piece of code that is tested to do it.
  Future<WallpaperPage> _requestPage(int pageKey) {
    final search = ref.read(searchWallpapersProvider);
    final WallpaperPage? previous = _lastPage;
    if (pageKey == 1 || previous == null) {
      return search(widget.query.atPage(pageKey));
    }
    return search.nextPageAfter(widget.query, previous);
  }

  /// Throws away the listing on screen and fetches page 1 of the current query.
  ///
  /// The [PagingController.fetchNextPage] is ours to make and is **not**
  /// redundant with the one [PagedLayoutBuilder] schedules for itself. That one
  /// is fired from `didUpdateWidget` only when the paging *state* is seen to
  /// change, and [PagingController.refresh] resets the state to its pristine
  /// value — which the layout is already holding whenever the opening fetch has
  /// not yet drawn a frame. `PagingState` compares by value, so pristine
  /// replacing pristine is no change at all: nothing re-fetches, while
  /// `refresh()` has already cleared the in-flight guard that would have let
  /// the opening fetch's result land. The grid spins forever, and only a fresh
  /// grid (a sorting tab) recovers.
  ///
  /// That is the cold-launch hang the tablet found (#hang, 2026-07-16). Two
  /// things rewrite the query while the opening fetch is still away: Android
  /// delivering its real display metrics after the first frame — which browse
  /// folds into every query as an *Automatic* resolution filter, so it happens
  /// on every launch, with no account and no saved filters needed — and
  /// `browseDefaultsProvider` resolving asynchronously. A release build is
  /// quick enough to land either inside that one-frame window; a debug build
  /// draws a frame first and recovers, which is why this only ever showed up on
  /// a real device in release.
  ///
  /// Asking for the page ourselves does not depend on the window at all. It
  /// cannot double-fetch: the guard `refresh()` clears is the same one that
  /// makes the layout's own scheduled call a no-op.
  void _retry() {
    _lastPage = null;
    _generation++;
    _paging
      ..refresh()
      ..fetchNextPage();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<WallpaperTag>>>(
      blockedTagsProvider,
      (
        AsyncValue<List<WallpaperTag>>? previous,
        AsyncValue<List<WallpaperTag>> next,
      ) {
        if (_blocklistChanged(previous, next)) unawaited(_reapplyBlocklist());
      },
    );
    return PagingListener<int, Wallpaper>(
      controller: _paging,
      builder: _grid,
    );
  }

  /// Whether the blocklist's effect on a search actually changed between
  /// [previous] and [next] — the only thing worth re-fetching for.
  ///
  /// Listening for `hasValue` alone is not that: a [FutureProvider] resolving
  /// for the first time (`AsyncLoading` → `AsyncData`) has a value where a
  /// moment ago it had none, so a plain `hasValue` re-fetches page 1 the
  /// instant the blocklist first loads — against the very blocklist the
  /// opening fetch already read for itself, since [SearchWallpapers] re-reads
  /// it on every call. Whether that costs a redundant request or nothing at
  /// all comes down to which resolves first, so it is a race rather than a
  /// steady cost; hence the gate.
  ///
  /// Compares tag *names*, not the tags: names are the shape a search filters
  /// on ([TagBlocklistRepository.blockedNames]), so an upstream rename that
  /// keeps its id is a genuine change here even though the tags compare equal
  /// (`WallpaperTag ==` is id-only, deliberately), and a set is order-free
  /// where the provider's most-recent-first list is not.
  bool _blocklistChanged(
    AsyncValue<List<WallpaperTag>>? previous,
    AsyncValue<List<WallpaperTag>> next,
  ) {
    final List<WallpaperTag>? before = previous?.value;
    final List<WallpaperTag>? after = next.value;
    if (before == null || after == null) return false;
    return !setEquals(_blockedNames(before), _blockedNames(after));
  }

  Set<String> _blockedNames(List<WallpaperTag> tags) => <String>{
    for (final WallpaperTag tag in tags) tag.name,
  };

  /// Re-fetches every page already on screen, in place, after a block or
  /// unblock — without going through [_retry]'s full reset.
  ///
  /// [_retry] clears the paging state and re-shows the loading indicator,
  /// which would yank the user back to the top of a listing they were mid-way
  /// through just for blocking one tag. This instead swaps each loaded page's
  /// *contents* for a freshly filtered fetch of the same page, leaving the
  /// scroll position exactly where it was — the wallpapers under the user's
  /// thumb may shift as blocked ones drop out, but the list itself doesn't
  /// jump. A page the user hasn't scrolled to yet already gets the current
  /// blocklist for free, since every fetch reads it fresh.
  Future<void> _reapplyBlocklist() async {
    final List<int>? keys = _paging.value.keys;
    if (keys == null || keys.isEmpty) return;
    final int generation = _generation;
    final search = ref.read(searchWallpapersProvider);
    // Reuses the pinned shuffle seed, or a random listing would reroll on
    // every block instead of quietly re-filtering the one it already has.
    final SearchQuery base = widget.query.copyWith(seed: _lastPage?.seed);
    final List<WallpaperPage> pages = await Future.wait(
      keys.map((int key) => search(base.atPage(key))),
    );
    if (!mounted) return;
    // A re-filter of the listing the user has already left must not land on the
    // one that replaced it — these are whole pages, so it would be visible.
    if (generation != _generation) return;
    _lastPage = pages.last;
    _paging.value = _paging.value.copyWith(
      pages: <List<Wallpaper>>[
        for (final WallpaperPage page in pages) page.wallpapers,
      ],
    );
  }

  /// This shelf's stable identity, which the Hero tags and the detail session
  /// both key off.
  String get _identity =>
      wallpaperListingIdentity(widget.galleryIdentity, widget.query);

  /// The name the active source calls itself, for a failure that has to say
  /// who refused.
  String get _sourceName => ref.read(activeWallpaperSourceProvider).displayName;

  Widget _grid(
    BuildContext context,
    PagingState<int, Wallpaper> state,
    NextPageCallback fetchNextPage,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Wallpaper> loaded = state.items ?? const <Wallpaper>[];
    return RefreshIndicator(
      onRefresh: () async => _retry(),
      child: loaded.isEmpty
          ? wallFirstPage(
              l10n,
              state,
              sourceName: _sourceName,
              onRetry: _retry,
            )
          : _wall(context, l10n, state, fetchNextPage, loaded, _identity),
    );
  }

  /// The wall itself, in justified rows, watching its own tail for the next
  /// page.
  ///
  /// Rows rather than masonry because masonry has no rows to read: it drops
  /// each tile into the shortest column, so the tile beside another is often
  /// the one *before* it, and the detail pager — which walks the list by index
  /// — looked like it skipped around. Here reading order is list order, so the
  /// pager, the session, and the index-keyed Hero tags all need no
  /// compensation.
  Widget _wall(
    BuildContext context,
    AppLocalizations l10n,
    PagingState<int, Wallpaper> state,
    NextPageCallback fetchNextPage,
    List<Wallpaper> loaded,
    String identity,
  ) {
    // Subscribing to the density is what keeps the top-up alive across a change
    // to it. The packing reads it one layer down, inside
    // `JustifiedWallpaperGrid`, so without a dependency here the wall re-packs
    // without `_wall` rebuilding — and the callback below, registered only
    // while building, would never be scheduled again. Going *Large → Small* is
    // exactly that transition: the same page that overflowed now leaves rows to
    // spare, which is how the device hit this with the scroll top-up already in
    // place (2026-07-19).
    TileDensityScope.of(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _topUpIfUnderfilled(state, fetchNextPage),
    );
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) =>
          _maybeFetchNext(notification, state, fetchNextPage),
      child: SelectableWallpaperShelf(
        wallpapers: loaded,
        // Nothing on this wall is favorited or downloaded by definition, so
        // both marks — and therefore both batch actions — say something here.
        actions: const <WallpaperBatchAction>[
          WallpaperBatchAction.favorite,
          WallpaperBatchAction.download,
        ],
        child: JustifiedWallpaperGrid(
          controller: _scroll,
          itemCount: loaded.length,
          aspectRatioOf: (int index) => loaded[index].resolution.aspectRatio,
          itemBuilder: (BuildContext context, int index, double _, double _) =>
              _tile(context, loaded, index, identity),
          footer: wallFooter(
            l10n,
            state,
            sourceName: _sourceName,
            onRetry: _retry,
          ),
        ),
      ),
    );
  }

  /// One tile, whose gestures depend on whether the wall is selecting.
  ///
  /// The context here is the one below `SelectableWallpaperShelf`'s scope,
  /// which is what lets both the tick and the quick sheet's *Select* row find
  /// the selection at all.
  Widget _tile(
    BuildContext context,
    List<Wallpaper> loaded,
    int index,
    String identity,
  ) {
    final gestures = selectableTileGestures(
      context: context,
      wallpaperKey: loaded[index].ref.key,
      onOpen: () => _openDetail(context, loaded, index),
      onLongPress: () => _openQuickActions(context, loaded, index),
    );
    return WallpaperTile(
      wallpaper: loaded[index],
      heroTag: shelfHeroTag(identity, loaded[index].ref.key, index),
      onTap: gestures.onTap,
      onLongPress: gestures.onLongPress,
    );
  }

  /// Asks for the next page once the user is within a screen of the end.
  ///
  /// Replaces the paged grid widget's own end-of-list trigger. Guarded on
  /// [PagingState.isLoading] as well as [PagingState.hasNextPage], or every
  /// scroll frame inside the threshold would fire another request.
  bool _maybeFetchNext(
    ScrollNotification notification,
    PagingState<int, Wallpaper> state,
    NextPageCallback fetchNextPage,
  ) {
    if (!state.hasNextPage || state.isLoading || state.error != null) {
      return false;
    }
    final ScrollMetrics metrics = notification.metrics;
    final double remaining = metrics.maxScrollExtent - metrics.pixels;
    if (remaining > metrics.viewportDimension) return false;
    fetchNextPage();
    return false;
  }

  /// Asks for the next page when the wall does not fill the viewport.
  ///
  /// [_maybeFetchNext] only ever runs off a [ScrollNotification], and a shelf
  /// shorter than its viewport emits none — there is nothing to scroll — so the
  /// check that would pass never runs and the listing stops at page one under a
  /// dead void. Reachable for real since the tile-density setting landed: at
  /// *Small* on a 2560x1600 tablet, Wallhaven's 24-item page leaves rows to
  /// spare, and the wall sat half-empty until a swipe at nothing shook a
  /// notification loose (device pass, 2026-07-19).
  ///
  /// Same lesson as the opening fetch in [initState] and as [_retry]: ask for
  /// the page rather than hoping a side effect notices. Guarded exactly as
  /// [_maybeFetchNext] is, so the two cannot both fire, and [PagingState
  /// .isLoading] keeps it to one request in flight while pages accumulate until
  /// the wall overflows or Wallhaven runs out.
  void _topUpIfUnderfilled(
    PagingState<int, Wallpaper> state,
    NextPageCallback fetchNextPage,
  ) {
    if (!mounted || !_scroll.hasClients) return;
    if (!state.hasNextPage || state.isLoading || state.error != null) return;
    if (_scroll.position.maxScrollExtent > 0) return;
    fetchNextPage();
  }

  void _openDetail(BuildContext context, List<Wallpaper> loaded, int index) {
    unawaited(
      openWallpaperDetail(
        context: context,
        bridge: _bridge,
        identity: _identity,
        query: widget.query,
        wallpapers: loaded,
        selectedIndex: index,
      ),
    );
  }

  void _openQuickActions(
    BuildContext context,
    List<Wallpaper> loaded,
    int index,
  ) {
    unawaited(
      openWallpaperQuickActions(
        context: context,
        ref: ref,
        wallpapers: loaded,
        index: index,
        openDetail: () => _openDetail(context, loaded, index),
      ),
    );
  }
}
