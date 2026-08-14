import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/dominant_swatch.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

/// [count] pixels of one colour, as an image's worth of votes.
List<int> _run(int rgb, int count) => List<int>.filled(count, rgb);

void main() {
  group('dominantSwatch', () {
    test('answers the colour the most pixels actually are', () {
      final WallpaperColor? swatch = dominantSwatch(<int>[
        ..._run(0x0066CC, 30),
        ..._run(0xCC3333, 10),
      ]);

      expect(swatch?.hex, '#0066cc');
    });

    test('is not an average of the picture', () {
      // The whole reason this buckets. Half vivid blue and half vivid orange
      // average to a muddy grey-brown that is nowhere in the image; the answer
      // has to be one of the two colours actually present.
      final WallpaperColor? swatch = dominantSwatch(<int>[
        ..._run(0x0066CC, 50),
        ..._run(0xFF6600, 49),
      ]);

      expect(swatch?.hex, '#0066cc');
    });

    test('lets a vivid subject win over a near-grey background', () {
      // The common photograph: mostly shadow and cloud, with one colour in it.
      // Counting the greys would describe every picture by its background.
      final WallpaperColor? swatch = dominantSwatch(<int>[
        ..._run(0x3A3B3C, 400),
        ..._run(0x707172, 300),
        ..._run(0xEA4C88, 40),
      ]);

      expect(swatch?.hex, '#ea4c88');
    });

    test('answers null for a picture made only of grey', () {
      // Same answer a Wallhaven wallpaper of four neutrals gets, and it must
      // be: one rule, or the same image tints on one site and not the other.
      expect(
        dominantSwatch(<int>[..._run(0x000000, 50), ..._run(0xBBBBBB, 50)]),
        isNull,
      );
    });

    test('answers null for no pixels at all', () {
      expect(dominantSwatch(const <int>[]), isNull);
    });

    test('averages within the winning bucket, not to its centre', () {
      // Two nearly-identical blues land in one bucket; the answer should be a
      // colour from that region rather than the bucket's arithmetic middle.
      final WallpaperColor? swatch = dominantSwatch(<int>[
        ..._run(0x0060C0, 10),
        ..._run(0x0068C8, 10),
      ]);

      expect(swatch?.hex, '#0064c4');
    });
  });
}
