import 'dart:async';

import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// Bridges a grid's [PagingController] into an open gallery session.
///
/// The viewer asks its session for more; the session calls back here, which
/// drives the grid's *own* next-page fetch and appends whatever new wallpapers
/// arrive. Going through the grid's controller is what preserves the live query
/// and the `random` shuffle seed — both live in the grid's fetch path, not in
/// the viewer — while keeping [GallerySessionController] free of the paging
/// package.
class GalleryPagingBridge {
  /// Bridges the grid's paging controller into sessions opened from it.
  GalleryPagingBridge(this._paging);

  final PagingController<int, Wallpaper> _paging;

  /// Fetches the grid's next page and appends its new items to [session].
  ///
  /// Appends nothing at the last page. When a page request fails and no items
  /// arrive, the fetch error is rethrown so the session can mark the request
  /// failed and offer a retry, leaving the selected image in place.
  Future<void> appendNextPageInto(
    GallerySessionController<Wallpaper> session,
  ) async {
    final int before = _loadedCount;
    await _awaitNextPage();
    final int after = _loadedCount;
    if (after > before) {
      session.append(_paging.value.items!.sublist(before));
      return;
    }
    final Object? error = _paging.value.error;
    // Re-surface the fetch failure so the session records it for retry; the
    // paging controller stores whatever the grid's fetch path threw.
    if (error != null) throw error; // ignore: only_throw_errors
  }

  int get _loadedCount => _paging.value.items?.length ?? 0;

  /// Completes when the paging controller settles its next-page fetch.
  ///
  /// `fetchNextPage` returns void and finishes asynchronously, so completion is
  /// observed through the controller's own loading flag rather than awaited.
  Future<void> _awaitNextPage() {
    final Completer<void> settled = Completer<void>();
    void onSettled() {
      if (_paging.value.isLoading) return;
      _paging.removeListener(onSettled);
      if (!settled.isCompleted) settled.complete();
    }

    _paging
      ..addListener(onSettled)
      ..fetchNextPage();
    if (!_paging.value.isLoading) onSettled();
    return settled.future;
  }
}
