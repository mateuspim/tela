import 'dart:async';

import 'package:flutter/foundation.dart';

/// Optional seam for asking a shelf to append more items in a later slice.
typedef GalleryRequestMore = FutureOr<void> Function();

/// Optional seam for warming one already-loaded gallery item.
typedef GalleryItemPrefetch<T> = FutureOr<void> Function(T item);

/// Optional stable identity of one gallery item, used to deduplicate appends.
typedef GalleryItemKey<T> = String Function(T item);

/// Owns one ordered, already-loaded gallery session.
///
/// This deliberately knows nothing about Riverpod, paging packages, or image
/// transports. Shelves hand it their current snapshot and may optionally
/// provide adapters for neighbour prefetch and pagination. When it nears the
/// end of its loaded items it asks the [requestMore] seam once — never the
/// transport — and appends whatever the shelf hands back.
final class GallerySessionController<T> extends ChangeNotifier {
  /// Creates a session positioned on [initialIndex].
  GallerySessionController({
    required String identity,
    required List<T> items,
    required int initialIndex,
    GalleryItemPrefetch<T>? prefetchItem,
    GalleryRequestMore? requestMore,
    GalleryItemKey<T>? itemKey,
  }) : assert(identity.isNotEmpty, 'identity must not be empty'),
       assert(items.isNotEmpty, 'a gallery session needs at least one item'),
       assert(
         initialIndex >= 0 && initialIndex < items.length,
         'initialIndex must select an item',
       ),
       identity = identity,
       _items = List<T>.unmodifiable(items),
       _selectedIndex = initialIndex,
       _prefetchItem = prefetchItem,
       _requestMore = requestMore,
       _itemKey = itemKey {
    _prefetchNeighbours();
    // Deferred so a shelf opened on its last tile still loads the next page,
    // without touching the request-more wiring before the caller finishes it.
    scheduleMicrotask(_maybeRequestMore);
  }

  /// A shelf within this many items of its end asks for the next page.
  static const int _requestMoreThreshold = 2;

  /// Stable identity of the shelf that created this session.
  final String identity;

  List<T> _items;
  int _selectedIndex;
  final GalleryItemPrefetch<T>? _prefetchItem;
  final GalleryRequestMore? _requestMore;
  final GalleryItemKey<T>? _itemKey;
  bool _isRequestingMore = false;
  bool _requestFailed = false;
  bool _disposed = false;

  /// The ordered snapshot currently reachable in the viewer.
  List<T> get items => _items;

  /// Zero-based selected position.
  int get selectedIndex => _selectedIndex;

  /// The item selected by every Detail surface and action.
  T get selectedItem => _items[_selectedIndex];

  /// Whether an already-loaded item exists before the selection.
  bool get canSelectPrevious => _selectedIndex > 0;

  /// Whether an already-loaded item exists after the selection.
  bool get canSelectNext => _selectedIndex + 1 < _items.length;

  /// Whether the creating shelf exposed a request-more operation.
  bool get canRequestMore => _requestMore != null;

  /// Whether a page request is currently outstanding.
  bool get isRequestingMore => _isRequestingMore;

  /// Whether the most recent page request failed and can be retried.
  bool get hasRequestFailed => _requestFailed;

  /// Selects [index], resets consumers through one notification, warms only its
  /// immediate neighbours, and asks for more items when it nears the end.
  bool select(int index) {
    RangeError.checkValidIndex(index, _items, 'index');
    if (index == _selectedIndex) return false;
    _selectedIndex = index;
    notifyListeners();
    _prefetchNeighbours();
    _maybeRequestMore();
    return true;
  }

  /// Selects the previous loaded item, if one exists.
  bool selectPrevious() {
    if (!canSelectPrevious) return false;
    return select(_selectedIndex - 1);
  }

  /// Selects the next loaded item, if one exists.
  bool selectNext() {
    if (!canSelectNext) return false;
    return select(_selectedIndex + 1);
  }

  /// Appends newly loaded items, skipping any whose key is already present.
  ///
  /// Order and the current selection are preserved: additions land at the end
  /// and never shift [selectedIndex], so the viewer stays on its image and Next
  /// simply becomes reachable.
  void append(Iterable<T> items) {
    if (_disposed) return;
    final List<T> additions = _deduplicated(items);
    if (additions.isEmpty) return;
    _items = List<T>.unmodifiable(<T>[..._items, ...additions]);
    notifyListeners();
    _prefetchNeighbours();
  }

  /// Asks the shelf for its next page, at most once at a time.
  ///
  /// A failed request is recorded rather than thrown, so an auto-trigger from
  /// [select] cannot surface as an unhandled async error; calling this again is
  /// the non-blocking retry path, and it leaves the selection untouched.
  Future<void> requestMore() async {
    final GalleryRequestMore? request = _requestMore;
    if (request == null || _isRequestingMore || _disposed) return;
    _isRequestingMore = true;
    _requestFailed = false;
    _notify();
    try {
      await request();
    } on Object {
      _requestFailed = true;
    } finally {
      _isRequestingMore = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<T> _deduplicated(Iterable<T> items) {
    final GalleryItemKey<T>? key = _itemKey;
    if (key == null) return List<T>.of(items);
    final Set<String> seen = _items.map(key).toSet();
    final List<T> additions = <T>[];
    for (final T item in items) {
      if (seen.add(key(item))) additions.add(item);
    }
    return additions;
  }

  void _maybeRequestMore() {
    if (!canRequestMore) return;
    if (_items.length - _selectedIndex > _requestMoreThreshold) return;
    unawaited(requestMore());
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _prefetchNeighbours() {
    final GalleryItemPrefetch<T>? prefetch = _prefetchItem;
    if (prefetch == null) return;
    if (canSelectPrevious) {
      unawaited(Future<void>.sync(() => prefetch(_items[_selectedIndex - 1])));
    }
    if (canSelectNext) {
      unawaited(Future<void>.sync(() => prefetch(_items[_selectedIndex + 1])));
    }
  }
}
