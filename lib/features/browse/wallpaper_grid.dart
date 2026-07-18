import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';
import 'package:tela/features/browse/gallery_paging_bridge.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_detail_args.dart';
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

  Widget _grid(
    BuildContext context,
    PagingState<int, Wallpaper> state,
    NextPageCallback fetchNextPage,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Wallpaper> loaded = state.items ?? const <Wallpaper>[];
    final String identity = wallpaperListingIdentity(
      widget.galleryIdentity,
      widget.query,
    );
    return RefreshIndicator(
      onRefresh: () async => _retry(),
      child: loaded.isEmpty
          ? _firstPage(context, l10n, state)
          : _wall(context, l10n, state, fetchNextPage, loaded, identity),
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
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) =>
          _maybeFetchNext(notification, state, fetchNextPage),
      child: JustifiedWallpaperGrid(
        itemCount: loaded.length,
        aspectRatioOf: (int index) => loaded[index].resolution.aspectRatio,
        itemBuilder: (BuildContext context, int index, double _, double _) =>
            WallpaperTile(
              wallpaper: loaded[index],
              heroTag: shelfHeroTag(identity, loaded[index].id, index),
              onTap: () => _openDetail(context, loaded, index),
            ),
        footer: _footer(l10n, state),
      ),
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

  /// What sits below the last row: nothing, a next-page spinner, or a retry.
  Widget? _footer(AppLocalizations l10n, PagingState<int, Wallpaper> state) {
    if (state.error != null) return _failure(l10n, state.error);
    if (!state.isLoading) return null;
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  /// The whole-screen state before any wallpaper has arrived.
  ///
  /// Kept scrollable so pull-to-refresh still works when there is nothing to
  /// scroll — a listing that came back empty or failed is exactly when the user
  /// reaches for it, and [RefreshIndicator] ignores a non-scrolling child.
  Widget _firstPage(
    BuildContext context,
    AppLocalizations l10n,
    PagingState<int, Wallpaper> state,
  ) {
    final Widget body = switch (state) {
      PagingState<int, Wallpaper>(error: final Object error?) => _failure(
        l10n,
        error,
      ),
      PagingState<int, Wallpaper>(isLoading: true) =>
        const WallpaperGridSkeleton(),
      _ => WallpaperStatusView(
        icon: Icons.search_off,
        message: l10n.browseEmpty,
      ),
    };
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Exactly the viewport's height, not a minimum: the skeleton packs
            // its rows against a bounded box and overruns it deliberately, so
            // an unbounded child here makes it size to infinity and throw.
            child: SizedBox(height: constraints.maxHeight, child: body),
          ),
    );
  }

  Widget _failure(AppLocalizations l10n, Object? error) {
    return WallpaperStatusView.failure(
      l10n: l10n,
      error: error,
      onRetry: _retry,
    );
  }

  void _openDetail(
    BuildContext context,
    List<Wallpaper> loaded,
    int selectedIndex,
  ) {
    unawaited(_pushDetail(context, loaded, selectedIndex));
  }

  Future<void> _pushDetail(
    BuildContext context,
    List<Wallpaper> loaded,
    int selectedIndex,
  ) async {
    // `late` so the request-more seam can hand the bridge the very session it
    // belongs to; the closure only runs once the viewer nears the loaded end.
    late final GallerySessionController<Wallpaper> session;
    session = createWallpaperGallerySession(
      context: context,
      identity: wallpaperListingIdentity(
        widget.galleryIdentity,
        widget.query,
      ),
      wallpapers: loaded,
      initialIndex: selectedIndex,
      requestMore: () => _bridge.appendNextPageInto(session),
    );
    try {
      await context.pushNamed<void>(
        TelaRoutes.detailName,
        pathParameters: <String, String>{
          'wallpaperId': session.selectedItem.id,
        },
        // The grid's own query travels with the session so a tag or colour
        // followed from the detail screen inherits the filters this listing is
        // under, not Browse's global ones (see WallpaperDetailArgs).
        extra: WallpaperDetailArgs(
          session: session,
          originFilters: widget.query,
        ),
      );
    } finally {
      session.dispose();
    }
  }
}
