import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/tile_density_scope.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/domain/models/tile_density.dart';

/// A phone and the SM-X730, in dips: the two surfaces the knob has to work on.
const double _phoneWidth = 390;
const double _tabletWidth = 1280;

/// An unfolded foldable, where medium and large round to the same column count
/// — the width that makes the fractional divisor load-bearing.
const double _foldableWidth = 500;

void main() {
  group('TileDensity', () {
    test('parses a stored constant name, and nothing else', () {
      expect(TileDensity.tryFromName('large'), TileDensity.large);
      expect(TileDensity.tryFromName('small'), TileDensity.small);
      // An absent or hand-edited row costs the preference, not the app: every
      // caller falls back to medium, the density tela has always drawn.
      expect(TileDensity.tryFromName(null), isNull);
      expect(TileDensity.tryFromName('enormous'), isNull);
      expect(TileDensity.tryFromName('Large'), isNull);
    });
  });

  group('row geometry across densities', () {
    test('a denser step draws shorter rows, on a phone and on a tablet', () {
      for (final double width in <double>[_phoneWidth, _tabletWidth]) {
        final double small = wallpaperRowHeight(width, TileDensity.small);
        final double medium = wallpaperRowHeight(width, TileDensity.medium);
        final double large = wallpaperRowHeight(width, TileDensity.large);
        expect(small, lessThan(medium), reason: 'small must shrink at $width');
        expect(large, greaterThan(medium), reason: 'large must grow at $width');
      }
    });

    test('a rounded column count would erase the knob at $_foldableWidth', () {
      // 500 / 220 and 500 / 320 both *round* to two columns — so deriving the
      // target height from a rounded count hands medium and large the identical
      // number, and "Large" visibly does nothing on this shelf. The divisor is
      // fractional for exactly this case; see wallpaperRowHeight. Pinning it at
      // the phone width instead would prove nothing, because 390 rounds to two
      // and one, which differ by accident.
      expect(
        wallpaperRowTileCap(_foldableWidth, TileDensity.medium),
        wallpaperRowTileCap(_foldableWidth, TileDensity.large),
        reason: 'the rounded counts must collide, or this test is vacuous',
      );
      expect(
        wallpaperRowHeight(_foldableWidth, TileDensity.large),
        greaterThan(
          wallpaperRowHeight(_foldableWidth, TileDensity.medium) * 1.2,
        ),
      );
    });

    test('the per-row cap moves with the density on a wide shelf', () {
      // The clamp is the other half of the knob: a fixed ceiling of six would
      // hand small exactly the row medium already draws on the tablet.
      expect(
        wallpaperRowTileCap(_tabletWidth, TileDensity.small),
        greaterThan(wallpaperRowTileCap(_tabletWidth, TileDensity.medium)),
      );
      expect(
        wallpaperRowTileCap(_tabletWidth, TileDensity.large),
        lessThan(wallpaperRowTileCap(_tabletWidth, TileDensity.medium)),
      );
    });

    test('medium is unchanged from what the wall drew before the setting', () {
      // The default density must not be a silent resize on upgrade: these are
      // the counts the shipped grid already packed at these widths.
      expect(wallpaperRowTileCap(_phoneWidth, TileDensity.medium), 2);
      expect(wallpaperRowTileCap(_tabletWidth, TileDensity.medium), 6);
    });
  });

  group('TileDensityScope', () {
    testWidgets('a shelf with no scope above it draws at medium', (
      WidgetTester tester,
    ) async {
      // Every widget test that mounts a shelf on its own relies on this.
      late TileDensity seen;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            seen = TileDensityScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(seen, TileDensity.medium);
    });

    testWidgets('the shelf resizes its tiles when the scope changes', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_grid(TileDensity.medium));
      final double atMedium = _firstTileHeight(tester);

      await tester.pumpWidget(_grid(TileDensity.large));
      final double atLarge = _firstTileHeight(tester);

      // The claim the whole slice rests on: the setting reaches the wall.
      expect(atLarge, greaterThan(atMedium));
    });
  });
}

/// The height the packed row assigned the first tile.
double _firstTileHeight(WidgetTester tester) {
  return tester.getSize(find.byKey(const ValueKey<int>(0))).height;
}

/// A justified shelf of same-shaped wallpapers under [density], on a phone.
Widget _grid(TileDensity density) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(_phoneWidth, 844)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: TileDensityScope(
        density: density,
        child: JustifiedWallpaperGrid(
          itemCount: 12,
          aspectRatioOf: (int index) => 0.5625,
          itemBuilder:
              (BuildContext context, int index, double width, double height) =>
                  SizedBox(key: ValueKey<int>(index)),
        ),
      ),
    ),
  );
}
