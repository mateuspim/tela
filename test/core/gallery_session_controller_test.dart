import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';

void main() {
  test('keeps stable identity, order, and exact starting index', () {
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'browse:latest',
          items: const <String>['a', 'b', 'c'],
          initialIndex: 1,
        );
    addTearDown(gallery.dispose);

    expect(gallery.identity, 'browse:latest');
    expect(gallery.items, <String>['a', 'b', 'c']);
    expect(gallery.selectedIndex, 1);
    expect(gallery.selectedItem, 'b');
  });

  test('previous and next stop at true loaded boundaries', () {
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'favorites',
          items: const <String>['a', 'b'],
          initialIndex: 0,
        );
    addTearDown(gallery.dispose);

    expect(gallery.canSelectPrevious, isFalse);
    expect(gallery.selectPrevious(), isFalse);
    expect(gallery.selectNext(), isTrue);
    expect(gallery.selectedItem, 'b');
    expect(gallery.canSelectNext, isFalse);
    expect(gallery.selectNext(), isFalse);
  });

  test('prefetches only immediate loaded neighbours after selection', () {
    final List<String> prefetched = <String>[];
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'linked:nature',
          items: const <String>['a', 'b', 'c', 'd', 'e'],
          initialIndex: 2,
          prefetchItem: prefetched.add,
        );
    addTearDown(gallery.dispose);

    expect(prefetched, <String>['b', 'd']);
    prefetched.clear();

    gallery.selectNext();

    expect(prefetched, <String>['c', 'e']);
  });

  test('append deduplicates by key, preserving order and selection', () {
    final GallerySessionController<_Item> gallery =
        GallerySessionController<_Item>(
          identity: 'browse:latest',
          items: const <_Item>[_Item('a'), _Item('b'), _Item('c')],
          initialIndex: 1,
          itemKey: (_Item item) => item.id,
        );
    addTearDown(gallery.dispose);

    gallery.append(const <_Item>[
      _Item('b'),
      _Item('d'),
      _Item('a'),
      _Item('e'),
    ]);

    expect(gallery.items.map((_Item item) => item.id).toList(), <String>[
      'a',
      'b',
      'c',
      'd',
      'e',
    ]);
    expect(gallery.selectedIndex, 1);
    expect(gallery.selectedItem.id, 'b');
  });

  test('appended items enable Next and update the position immediately', () {
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'browse:hot',
          items: const <String>['a', 'b'],
          initialIndex: 1,
        );
    addTearDown(gallery.dispose);

    expect(gallery.canSelectNext, isFalse);
    expect(gallery.items.length, 2);

    gallery.append(const <String>['c', 'd']);

    expect(gallery.canSelectNext, isTrue);
    expect(gallery.selectedIndex, 1);
    expect(gallery.items.length, 4);
  });

  test('nearing the end asks for more exactly once, on select', () async {
    int requests = 0;
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'browse:hot',
          items: const <String>['a', 'b', 'c', 'd', 'e'],
          initialIndex: 0,
          requestMore: () => requests++,
        );
    addTearDown(gallery.dispose);
    await _drainMicrotasks();
    expect(requests, 0, reason: 'the head of a full shelf asks for nothing');

    gallery.select(3);
    await _drainMicrotasks();

    expect(requests, 1);
  });

  test('a shelf opened on its last item requests more once mounted', () async {
    int requests = 0;
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'browse:hot',
          items: const <String>['a', 'b', 'c'],
          initialIndex: 2,
          requestMore: () => requests++,
        );
    addTearDown(gallery.dispose);

    await _drainMicrotasks();

    expect(requests, 1);
  });

  test('allows only one outstanding page request at a time', () async {
    int started = 0;
    final Completer<void> inFlight = Completer<void>();
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'browse:hot',
          items: const <String>['a', 'b'],
          initialIndex: 1,
          requestMore: () {
            started++;
            return inFlight.future;
          },
        );
    addTearDown(gallery.dispose);
    await _drainMicrotasks();

    expect(started, 1);
    expect(gallery.isRequestingMore, isTrue);

    await gallery.requestMore();
    expect(started, 1, reason: 'a second request must not start mid-flight');

    inFlight.complete();
    await _drainMicrotasks();
    expect(gallery.isRequestingMore, isFalse);
  });

  test('records a failed request and retries on the next call', () async {
    int attempts = 0;
    late final GallerySessionController<String> gallery;
    gallery = GallerySessionController<String>(
      identity: 'browse:hot',
      items: const <String>['a', 'b'],
      initialIndex: 1,
      requestMore: () {
        attempts++;
        if (attempts == 1) throw Exception('page fetch failed');
        gallery.append(const <String>['c']);
      },
    );
    addTearDown(gallery.dispose);
    await _drainMicrotasks();

    expect(attempts, 1);
    expect(gallery.hasRequestFailed, isTrue);
    expect(gallery.items, <String>['a', 'b']);

    await gallery.requestMore();

    expect(attempts, 2);
    expect(gallery.hasRequestFailed, isFalse);
    expect(gallery.items, <String>['a', 'b', 'c']);
  });

  test('a shelf without a request-more seam never requests', () async {
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'favorites',
          items: const <String>['a', 'b'],
          initialIndex: 1,
        );
    addTearDown(gallery.dispose);

    await _drainMicrotasks();

    expect(gallery.canRequestMore, isFalse);
    expect(gallery.isRequestingMore, isFalse);
    await gallery.requestMore();
    expect(gallery.isRequestingMore, isFalse);
  });
}

/// Yields until scheduled microtasks (the deferred initial request) settle.
Future<void> _drainMicrotasks() => Future<void>.delayed(Duration.zero);

class _Item {
  const _Item(this.id);
  final String id;
}
