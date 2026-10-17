import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/batch_routing.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';

void main() {
  // Owner, 2026-10-16: a mixed batch was split across the gallery and the
  // card because each image followed its own purity's destination.
  group('an explicit batch', () {
    const BatchRouting routing = BatchRouting(<Purity>{
      Purity.sfw,
      Purity.sketchy,
      Purity.nsfw,
    });

    test('is routed as explicit alone', () {
      expect(routing.isExplicit, isTrue);
      expect(routing.purities, <Purity>{Purity.nsfw});
    });

    test('routes every wallpaper in it as explicit', () {
      final List<Wallpaper> routed = routing.apply(<Wallpaper>[
        _wallpaper('a', Purity.sfw),
        _wallpaper('b', Purity.sketchy),
        _wallpaper('c', Purity.nsfw),
      ]);

      expect(routed.every((Wallpaper w) => w.isNsfw), isTrue);
      // Same wallpapers, same order: only the routing changed.
      expect(routed.map((Wallpaper w) => w.id), <String>['a', 'b', 'c']);
    });
  });

  group('a batch with nothing explicit', () {
    const BatchRouting routing = BatchRouting(<Purity>{
      Purity.sfw,
      Purity.sketchy,
    });

    test('keeps its own purities', () {
      expect(routing.isExplicit, isFalse);
      expect(routing.purities, <Purity>{Purity.sfw, Purity.sketchy});
    });

    test('leaves each wallpaper as it was', () {
      final Wallpaper safe = _wallpaper('a', Purity.sfw);

      expect(routing.apply(<Wallpaper>[safe]).single.purity, Purity.sfw);
    });
  });

  test('routedAsExplicit keeps everything but the purity', () {
    final Wallpaper safe = _wallpaper('a', Purity.sfw);
    final Wallpaper routed = safe.routedAsExplicit();

    expect(routed.purity, Purity.nsfw);
    expect(routed.ref, safe.ref);
    expect(routed.fullImageUrl, safe.fullImageUrl);
    expect(routed.resolution, safe.resolution);
  });
}

Wallpaper _wallpaper(String id, Purity purity) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: purity,
  category: Category.general,
  colors: const <String>[],
);
