import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/wallpaper_color.dart';

void main() {
  group('WallpaperColor', () {
    test('speaks both Wallhaven dialects: #rrggbb in, rrggbb out', () {
      // A wallpaper's JSON carries the hash; the `colors` query param rejects
      // it. Getting this backwards silently returns zero results.
      expect(WallpaperColor('#0066cc').hex, '#0066cc');
      expect(WallpaperColor('#0066cc').toApiValue(), '0066cc');
    });

    test('normalizes case, so #FFCC33 and #ffcc33 are one colour', () {
      expect(WallpaperColor('#FFCC33'), WallpaperColor('#ffcc33'));
      expect(WallpaperColor('#FFCC33').toApiValue(), 'ffcc33');
    });

    test('rejects anything that is not a #rrggbb colour', () {
      expect(() => WallpaperColor('0066cc'), throwsArgumentError);
      expect(() => WallpaperColor('#06c'), throwsArgumentError);
      expect(() => WallpaperColor('#gggggg'), throwsArgumentError);
      expect(() => WallpaperColor(''), throwsArgumentError);
    });

    test('names the offending value and the expected shape when it throws', () {
      expect(
        () => WallpaperColor('chartreuse'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            allOf(contains('#rrggbb'), contains('chartreuse')),
          ),
        ),
      );
    });

    test('exposes RGB channels only, leaving alpha to the caller', () {
      // The domain imports no Color and has no opinion about opacity.
      expect(WallpaperColor('#000000').rgb, 0x000000);
      expect(WallpaperColor('#ffffff').rgb, 0xffffff);
      expect(WallpaperColor('#ea4c88').rgb, 0xea4c88);
    });
  });

  group('WallpaperColor.readAll', () {
    test('drops an unreadable colour rather than the whole list', () {
      // The display path. One colour Wallhaven spells in a shape we do not
      // know should cost that swatch, not the detail screen it sits on.
      final List<WallpaperColor> read = WallpaperColor.readAll(<String>[
        '#660000',
        'rebeccapurple',
        '#424153',
      ]);

      expect(read, <WallpaperColor>[
        WallpaperColor('#660000'),
        WallpaperColor('#424153'),
      ]);
    });

    test('reads an empty list as no colours, not as a failure', () {
      expect(WallpaperColor.readAll(<String>[]), isEmpty);
    });
  });

  group('WallpaperColor.palette', () {
    test("offers Wallhaven's 29 searchable colours", () {
      expect(WallpaperColor.palette, hasLength(29));
    });

    test('holds no duplicates — a repeated swatch is a dead chip', () {
      final Set<WallpaperColor> unique = WallpaperColor.palette.toSet();

      expect(unique, hasLength(WallpaperColor.palette.length));
    });

    test('is entirely #rrggbb, so every swatch encodes to a query param', () {
      for (final WallpaperColor color in WallpaperColor.palette) {
        expect(WallpaperColor(color.hex), color);
        expect(color.toApiValue(), hasLength(6));
      }
    });

    test('contains the colours the search fixture reports', () {
      // Wallhaven quantizes a wallpaper's colours down to this same palette, so
      // a colour seen on a detail screen must be one the filter can search for.
      expect(WallpaperColor.palette, contains(WallpaperColor('#660000')));
      expect(WallpaperColor.palette, contains(WallpaperColor('#000000')));
      expect(WallpaperColor.palette, contains(WallpaperColor('#424153')));
    });
  });
}
