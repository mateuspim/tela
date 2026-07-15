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

  test('exposes request-more and append seams without invoking them', () async {
    int requests = 0;
    final GallerySessionController<String> gallery =
        GallerySessionController<String>(
          identity: 'browse:hot',
          items: const <String>['a'],
          initialIndex: 0,
          requestMore: () => requests++,
        );
    addTearDown(gallery.dispose);

    expect(gallery.canRequestMore, isTrue);
    expect(requests, 0);
    gallery.append(const <String>['b']);
    expect(gallery.items, <String>['a', 'b']);
    expect(requests, 0);

    await gallery.requestMore();
    expect(requests, 1);
  });
}
