import 'dart:async';

import 'package:flutter/foundation.dart';

/// Optional seam for asking a shelf to append more items in a later slice.
typedef GalleryRequestMore = FutureOr<void> Function();

/// Optional seam for warming one already-loaded gallery item.
typedef GalleryItemPrefetch<T> = FutureOr<void> Function(T item);

/// Owns one ordered, already-loaded gallery session.
///
/// This deliberately knows nothing about Riverpod, paging packages, or image
/// transports. Shelves hand it their current snapshot and may optionally
/// provide adapters for neighbour prefetch and future pagination.
final class GallerySessionController<T> extends ChangeNotifier {
  /// Creates a session positioned on [initialIndex].
  GallerySessionController({
    required String identity,
    required List<T> items,
    required int initialIndex,
    GalleryItemPrefetch<T>? prefetchItem,
    GalleryRequestMore? requestMore,
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
       _requestMore = requestMore {
    _prefetchNeighbours();
  }

  /// Stable identity of the shelf that created this session.
  final String identity;

  List<T> _items;
  int _selectedIndex;
  final GalleryItemPrefetch<T>? _prefetchItem;
  final GalleryRequestMore? _requestMore;

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

  /// Whether the creating shelf exposed a later request-more operation.
  bool get canRequestMore => _requestMore != null;

  /// Selects [index], resets consumers through one notification, and warms
  /// only its immediate neighbours.
  bool select(int index) {
    RangeError.checkValidIndex(index, _items, 'index');
    if (index == _selectedIndex) return false;
    _selectedIndex = index;
    notifyListeners();
    _prefetchNeighbours();
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

  /// Makes newly loaded items reachable without coupling this type to paging.
  ///
  /// This slice does not call it; it is the append seam for Browse pagination.
  void append(Iterable<T> items) {
    final List<T> additions = List<T>.of(items);
    if (additions.isEmpty) return;
    _items = List<T>.unmodifiable(<T>[..._items, ...additions]);
    notifyListeners();
    _prefetchNeighbours();
  }

  /// Invokes the optional request-more seam without assuming its transport.
  Future<void> requestMore() async {
    await _requestMore?.call();
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
