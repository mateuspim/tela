import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/ambient_seed.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

void main() {
  group('ambientSeed', () {
    test("takes the wallpaper's first colour when it has a hue", () {
      final WallpaperColor? seed = ambientSeed(<String>['#660000', '#0066cc']);

      expect(seed?.hex, '#660000');
    });

    test('passes over leading neutrals to reach one that can seed', () {
      // Wallhaven orders by dominance, and a photograph is very often mostly
      // black or mostly white — so this is the common case, not the corner.
      final WallpaperColor? seed = ambientSeed(<String>[
        '#000000',
        '#cccccc',
        '#ea4c88',
      ]);

      expect(seed?.hex, '#ea4c88');
    });

    test('answers null when every colour is neutral', () {
      // A greyscale wallpaper getting no tint is the correct answer. The
      // caller leaves the theme alone; it does not paint a grey one.
      final WallpaperColor? seed = ambientSeed(<String>[
        '#000000',
        '#999999',
        '#cccccc',
        '#ffffff',
      ]);

      expect(seed, isNull);
    });

    test('answers null for a source that reports no colours', () {
      // Konachan, whose mapper hands over an empty list.
      expect(ambientSeed(const <String>[]), isNull);
    });

    test('ignores an unreadable colour rather than throwing on it', () {
      // Same tolerance as WallpaperColor.readAll: one bad value costs that
      // value, never the screen.
      final WallpaperColor? seed = ambientSeed(<String>[
        'chartreuse',
        '#669900',
      ]);

      expect(seed?.hex, '#669900');
    });

    test('allows a low-chroma colour through', () {
      // #424153 is the palette's muted slate. It is not achromatic, and a
      // muted wallpaper earning a muted tint is an honest answer — the rule
      // rejects "no hue at all", not "little hue".
      final WallpaperColor? seed = ambientSeed(<String>['#424153']);

      expect(seed?.hex, '#424153');
    });

    test("rejects a grey that is not one of the palette's four", () {
      // The rule computes chroma rather than naming the neutrals, so a colour
      // Wallhaven has not shipped yet is still refused. Widening the palette
      // must not mean widening a list somebody forgot.
      expect(ambientSeed(<String>['#7f7f7f']), isNull);
    });
  });
}
