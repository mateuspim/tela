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
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';
import 'package:tela/domain/use_cases/search_wallpapers.dart';
import 'package:tela/features/browse/gallery_paging_bridge.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/detail/wallpaper_gallery_session.dart';
import 'package:tela/features/settings/blocked_tags_providers.dart';

/// An infinite, masonry-packed grid of wallpapers for one [query].
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

  @override
  void initState() {
    super.initState();
    _paging = PagingController<int, Wallpaper>(
      getNextPageKey: _nextPageKey,
      fetchPage: _fetchPage,
    );
    _bridge = GalleryPagingBridge(_paging);
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
    final WallpaperPage page = await _requestPage(pageKey);
    _lastPage = page;
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

  void _retry() {
    _lastPage = null;
    _paging.refresh();
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
    final search = ref.read(searchWallpapersProvider);
    // Reuses the pinned shuffle seed, or a random listing would reroll on
    // every block instead of quietly re-filtering the one it already has.
    final SearchQuery base = widget.query.copyWith(seed: _lastPage?.seed);
    final List<WallpaperPage> pages = await Future.wait(
      keys.map((int key) => search(base.atPage(key))),
    );
    if (!mounted) return;
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
      child: PagedMasonryGridView<int, Wallpaper>.count(
        state: state,
        fetchNextPage: fetchNextPage,
        crossAxisCount: wallpaperGridColumns(context),
        mainAxisSpacing: wallpaperGridSpacing,
        crossAxisSpacing: wallpaperGridSpacing,
        padding: wallpaperGridPadding(context),
        builderDelegate: PagedChildBuilderDelegate<Wallpaper>(
          itemBuilder: (BuildContext context, Wallpaper wallpaper, int index) =>
              WallpaperTile(
                wallpaper: wallpaper,
                heroTag: shelfHeroTag(identity, wallpaper.id, index),
                onTap: () => _openDetail(context, loaded, index),
              ),
          firstPageErrorIndicatorBuilder: (BuildContext context) =>
              _failure(l10n, state.error),
          newPageErrorIndicatorBuilder: (BuildContext context) =>
              _failure(l10n, state.error),
          noItemsFoundIndicatorBuilder: (BuildContext context) =>
              WallpaperStatusView(
                icon: Icons.search_off,
                message: l10n.browseEmpty,
              ),
        ),
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
        extra: session,
      );
    } finally {
      session.dispose();
    }
  }
}
