import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/wallpaper_failure_text.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

/// An infinite, masonry-packed grid of wallpapers for one [query].
///
/// Owns its paging state, so each browse tab scrolls independently and keeps
/// its position when you switch away and back.
class WallpaperGrid extends ConsumerStatefulWidget {
  /// Creates a grid showing results for [query].
  const WallpaperGrid({required this.query, super.key});

  /// The listing to show. Page number is managed by the grid, not the caller.
  final SearchQuery query;

  @override
  ConsumerState<WallpaperGrid> createState() => _WallpaperGridState();
}

class _WallpaperGridState extends ConsumerState<WallpaperGrid> {
  late final PagingController<int, Wallpaper> _paging;

  /// The most recent page, kept so the next fetch can inherit its shuffle seed.
  WallpaperPage? _lastPage;

  @override
  void initState() {
    super.initState();
    _paging = PagingController<int, Wallpaper>(
      getNextPageKey: _nextPageKey,
      fetchPage: _fetchPage,
    );
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

  /// Columns sized by available width, not hardcoded.
  ///
  /// Two columns is right on a phone and absurd on a tablet, where it yields
  /// two ~1200px-wide tiles. Targets a tile around [_targetTileWidth] wide.
  int _columnsFor(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    return (width / _targetTileWidth).round().clamp(2, 6);
  }

  /// Logical width we aim each tile at, in dips.
  static const double _targetTileWidth = 220;

  @override
  Widget build(BuildContext context) {
    return PagingListener<int, Wallpaper>(
      controller: _paging,
      builder: _grid,
    );
  }

  Widget _grid(
    BuildContext context,
    PagingState<int, Wallpaper> state,
    NextPageCallback fetchNextPage,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: () async => _retry(),
      child: PagedMasonryGridView<int, Wallpaper>.count(
        state: state,
        fetchNextPage: fetchNextPage,
        crossAxisCount: _columnsFor(context),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        padding: const EdgeInsets.all(8),
        builderDelegate: PagedChildBuilderDelegate<Wallpaper>(
          itemBuilder: (BuildContext context, Wallpaper wallpaper, int index) =>
              WallpaperTile(
                wallpaper: wallpaper,
                onTap: () => _openDetail(context, wallpaper),
              ),
          firstPageErrorIndicatorBuilder: (BuildContext context) =>
              _error(context, l10n, state.error),
          newPageErrorIndicatorBuilder: (BuildContext context) =>
              _error(context, l10n, state.error),
          noItemsFoundIndicatorBuilder: (BuildContext context) =>
              Center(child: Text(l10n.browseEmpty)),
        ),
      ),
    );
  }

  Widget _error(BuildContext context, AppLocalizations l10n, Object? error) {
    final String message = error is WallhavenFailure
        ? localizedFailure(l10n, error)
        : l10n.errorUnexpected;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(message, textAlign: TextAlign.center),
          ),
          FilledButton.tonal(
            onPressed: _retry,
            child: Text(l10n.actionRetry),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, Wallpaper wallpaper) {
    unawaited(
      context.pushNamed(
        TelaRoutes.detailName,
        pathParameters: <String, String>{'wallpaperId': wallpaper.id},
        extra: wallpaper,
      ),
    );
  }
}
