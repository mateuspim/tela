import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/ui/justified_rows.dart';

/// Every index, row by row, as the eye would read them.
List<int> _readingOrder(List<JustifiedRow> rows) => <int>[
  for (final JustifiedRow row in rows)
    for (final JustifiedTile tile in row.tiles) tile.index,
];

double _rowWidth(JustifiedRow row, double spacing) {
  final double tiles = row.tiles.fold(
    0,
    (double sum, JustifiedTile tile) => sum + tile.width,
  );
  return tiles + spacing * (row.tiles.length - 1);
}

void main() {
  group('justifiedRows', () {
    test('reading order is always the source order', () {
      // The whole reason this layout exists: no tile may ever overtake another.
      final List<double> ratios = <double>[
        16 / 9,
        9 / 16,
        1,
        21 / 9,
        3 / 4,
        4 / 3,
        9 / 16,
        2,
      ];

      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: ratios,
        availableWidth: 1200,
        targetRowHeight: 240,
        spacing: 12,
        maxPerRow: 8,
      );

      expect(_readingOrder(rows), <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('every wallpaper appears exactly once', () {
      final List<double> ratios = List<double>.generate(
        37,
        (int i) => 0.4 + (i % 7) * 0.5,
      );

      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: ratios,
        availableWidth: 1000,
        targetRowHeight: 200,
        spacing: 8,
        maxPerRow: 8,
      );

      expect(_readingOrder(rows), List<int>.generate(37, (int i) => i));
    });

    test('full rows span the available width', () {
      final List<double> ratios = List<double>.filled(12, 16 / 9);

      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: ratios,
        availableWidth: 1200,
        targetRowHeight: 200,
        spacing: 12,
        maxPerRow: 8,
      );

      // The last row is deliberately not stretched, so check the closed ones.
      for (final JustifiedRow row in rows.take(rows.length - 1)) {
        expect(_rowWidth(row, 12), closeTo(1200, 1e-6));
      }
    });

    test('keeps every tile at its true aspect ratio', () {
      final List<double> ratios = <double>[16 / 9, 9 / 16, 1, 4 / 3, 21 / 9];

      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: ratios,
        availableWidth: 900,
        targetRowHeight: 180,
        spacing: 10,
        maxPerRow: 8,
      );

      for (final JustifiedRow row in rows) {
        for (final JustifiedTile tile in row.tiles) {
          expect(tile.width / tile.height, closeTo(ratios[tile.index], 1e-9));
        }
      }
    });

    test('shares one height across a row', () {
      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: <double>[16 / 9, 9 / 16, 1, 4 / 3, 2, 3],
        availableWidth: 1000,
        targetRowHeight: 200,
        spacing: 12,
        maxPerRow: 8,
      );

      for (final JustifiedRow row in rows) {
        for (final JustifiedTile tile in row.tiles) {
          expect(tile.height, row.height);
        }
      }
    });

    test('caps a trailing row at the height of the row above it', () {
      // Three of these close a row exactly; the fourth is left over and alone.
      // Filling the width would make that one tile 600 tall — taller than the
      // wall it trails — so it stops at the rhythm the row above set.
      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: <double>[2, 2, 2, 2],
        availableWidth: 1200,
        targetRowHeight: 200,
        spacing: 12,
        maxPerRow: 8,
      );

      expect(rows, hasLength(2));
      expect(rows.last.tiles, hasLength(1));
      expect(rows.last.height, 200);
      expect(_rowWidth(rows.last, 12), lessThan(1200));
    });

    test('a trailing row that can fill the width without towering does', () {
      // Two wide tiles trailing a tall row of portraits: filling costs only
      // 294 of the 411 the row above stands at, so they fill rather than
      // leaving a gap.
      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: <double>[
          1080 / 2400,
          1080 / 2400,
          1080 / 2400,
          1080 / 2400,
          2,
          2,
        ],
        availableWidth: 1200,
        targetRowHeight: 123,
        spacing: 12,
        maxPerRow: 4,
      );

      expect(rows, hasLength(2));
      expect(rows.last.tiles, hasLength(2));
      expect(_rowWidth(rows.last, 12), closeTo(1200, 1e-6));
      expect(rows.last.height, lessThan(rows.first.height));
    });

    test('a lone leftover on an empty shelf still cannot tower', () {
      // No row above to borrow a rhythm from, so the target height is the cap.
      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: <double>[1080 / 2400],
        availableWidth: 1200,
        targetRowHeight: 200,
        spacing: 12,
        maxPerRow: 4,
      );

      expect(rows.single.height, 200);
    });

    test('a taller target row holds fewer wallpapers', () {
      final List<double> ratios = List<double>.filled(24, 16 / 9);

      final List<JustifiedRow> shortRows = justifiedRows(
        aspectRatios: ratios,
        availableWidth: 1200,
        targetRowHeight: 140,
        spacing: 12,
        maxPerRow: 8,
      );
      final List<JustifiedRow> tallRows = justifiedRows(
        aspectRatios: ratios,
        availableWidth: 1200,
        targetRowHeight: 320,
        spacing: 12,
        maxPerRow: 8,
      );

      expect(
        tallRows.first.tiles.length,
        lessThan(shortRows.first.tiles.length),
      );
    });

    test('appending items cannot disturb the rows already closed', () {
      // The pagination guarantee: page two may only re-pack the partial row.
      final List<double> firstPage = <double>[16 / 9, 4 / 3, 1, 9 / 16, 21 / 9];
      final List<double> bothPages = <double>[...firstPage, 3 / 2, 1, 16 / 9];

      final List<JustifiedRow> before = justifiedRows(
        aspectRatios: firstPage,
        availableWidth: 1000,
        targetRowHeight: 200,
        spacing: 12,
        maxPerRow: 8,
      );
      final List<JustifiedRow> after = justifiedRows(
        aspectRatios: bothPages,
        availableWidth: 1000,
        targetRowHeight: 200,
        spacing: 12,
        maxPerRow: 8,
      );

      final int closed = before.length - 1;
      for (int row = 0; row < closed; row++) {
        expect(after[row].height, closeTo(before[row].height, 1e-9));
        expect(
          after[row].tiles.map((JustifiedTile t) => t.index),
          before[row].tiles.map((JustifiedTile t) => t.index),
        );
      }
    });

    test('never puts more than the cap in one row', () {
      // Portrait wallpapers are narrow, so height alone would fit a dozen of
      // them across a wide shelf before the row was short enough to close.
      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: List<double>.filled(24, 1080 / 2400),
        availableWidth: 776,
        targetRowHeight: 123,
        spacing: 12,
        maxPerRow: 4,
      );

      for (final JustifiedRow row in rows) {
        expect(row.tiles.length, lessThanOrEqualTo(4));
      }
      expect(_readingOrder(rows), List<int>.generate(24, (int i) => i));
    });

    test('a capped row of portraits is tall, not a strip of slivers', () {
      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: List<double>.filled(8, 1080 / 2400),
        availableWidth: 776,
        targetRowHeight: 123,
        spacing: 12,
        maxPerRow: 4,
      );

      // Four phone-shaped tiles across 776dip: each still ~185 wide, the same
      // width the masonry column gave them, and correspondingly tall.
      expect(rows.first.tiles.first.width, closeTo(185, 2));
      expect(rows.first.height, greaterThan(300));
    });

    test('rejects a cap below one tile', () {
      expect(
        () => justifiedRows(
          aspectRatios: <double>[1],
          availableWidth: 1000,
          targetRowHeight: 200,
          spacing: 12,
          maxPerRow: 0,
        ),
        throwsArgumentError,
      );
    });

    test('handles an empty shelf', () {
      expect(
        justifiedRows(
          aspectRatios: <double>[],
          availableWidth: 1000,
          targetRowHeight: 200,
          spacing: 12,
          maxPerRow: 8,
        ),
        isEmpty,
      );
    });

    test('puts a lone wallpaper in its own row at the target height', () {
      final List<JustifiedRow> rows = justifiedRows(
        aspectRatios: <double>[9 / 16],
        availableWidth: 1000,
        targetRowHeight: 200,
        spacing: 12,
        maxPerRow: 8,
      );

      expect(rows, hasLength(1));
      expect(rows.single.tiles.single.index, 0);
      expect(rows.single.height, 200);
    });

    test('rejects a non-positive width, target height, or ratio', () {
      expect(
        () => justifiedRows(
          aspectRatios: <double>[1],
          availableWidth: 0,
          targetRowHeight: 200,
          spacing: 12,
          maxPerRow: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => justifiedRows(
          aspectRatios: <double>[1],
          availableWidth: 1000,
          targetRowHeight: 0,
          spacing: 12,
          maxPerRow: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => justifiedRows(
          aspectRatios: <double>[0],
          availableWidth: 1000,
          targetRowHeight: 200,
          spacing: 12,
          maxPerRow: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => justifiedRows(
          aspectRatios: <double>[1],
          availableWidth: 1000,
          targetRowHeight: 200,
          spacing: -1,
          maxPerRow: 8,
        ),
        throwsArgumentError,
      );
    });
  });
}
