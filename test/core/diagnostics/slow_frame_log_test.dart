import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/diagnostics/slow_frame_log.dart';

/// The probe that has to answer what "poor performance three pages deep"
/// actually is, off the release build the tablet runs.
///
/// It is measurement rather than behaviour, so what is pinned is the thing a
/// measurement must not get wrong: never lying about the count, never writing
/// when there is nothing to say, and never costing anything while frames are
/// on time.
void main() {
  test('says nothing at all while every frame is on time', () {
    // The state the app is in almost always. A probe that wrote a line per
    // frame would be its own performance problem, and would drown the log it
    // exists to be read from.
    final List<String> written = <String>[];
    final SlowFrameLog log = _log(written);

    for (int frame = 0; frame < 500; frame++) {
      log.observe(
        build: const Duration(milliseconds: 4),
        raster: const Duration(milliseconds: 6),
      );
    }

    expect(written, isEmpty);
  });

  test('a late raster counts even when the build was quick', () {
    // Decode thrash shows up in *raster*, not in build — which is the whole
    // hypothesis this exists to test. Watching build alone would miss it.
    final List<String> written = <String>[];
    final SlowFrameLog log = _log(written, batch: 2);

    for (int frame = 0; frame < 2; frame++) {
      log.observe(
        build: const Duration(milliseconds: 2),
        raster: const Duration(milliseconds: 80),
      );
    }

    expect(_lines(written).single['slow'], 2);
    expect(_lines(written).single['worstRasterMs'], 80);
  });

  test('reports the worst frame in the batch, not the last', () {
    // A run of jank is judged by how bad it got. Reporting the last frame
    // would make a batch that ended calmly look like it was.
    final List<String> written = <String>[];

    _log(written, batch: 3)
      ..observe(build: const Duration(milliseconds: 40), raster: Duration.zero)
      ..observe(build: const Duration(milliseconds: 90), raster: Duration.zero)
      ..observe(build: const Duration(milliseconds: 33), raster: Duration.zero);

    expect(_lines(written).single['worstBuildMs'], 90);
  });

  test('one line per batch, and the running total keeps counting', () {
    // The rate limit. A wall that janks for a minute must cost a handful of
    // lines, while the total still says how many frames that really was.
    final List<String> written = <String>[];
    final SlowFrameLog log = _log(written, batch: 10);

    for (int frame = 0; frame < 25; frame++) {
      log.observe(
        build: const Duration(milliseconds: 50),
        raster: Duration.zero,
      );
    }

    final List<Map<String, Object?>> lines = _lines(written);
    expect(lines.length, 2, reason: '25 slow frames is two full batches');
    expect(lines.map((Map<String, Object?> l) => l['slowTotal']), <int>[
      10,
      20,
    ]);
  });

  test('carries what the decode cache was holding at the time', () {
    // The numbers the deep-scroll question turns on: `ImageCache` evicts by
    // bytes, so a wall over its budget re-decodes what the user scrolls back
    // over. Without these the line would say a wall was slow and not why.
    final List<String> written = <String>[];
    _log(
      written,
      batch: 1,
    ).observe(build: const Duration(milliseconds: 50), raster: Duration.zero);

    final Map<String, Object?> line = _lines(written).single;
    expect(line['imagesCached'], 312);
    expect(line['imageBytes'], 98000000);
    expect(line['imagesLive'], 120);
  });

  test('a batch is not counted twice', () {
    // The failure that would make every number here a lie: leaving the
    // gathered frames in place after writing them.
    final List<String> written = <String>[];
    final SlowFrameLog log = _log(written, batch: 2);

    for (int frame = 0; frame < 4; frame++) {
      log.observe(
        build: const Duration(milliseconds: 50),
        raster: Duration.zero,
      );
    }

    expect(_lines(written).map((Map<String, Object?> l) => l['slow']), <int>[
      2,
      2,
    ]);
  });
}

SlowFrameLog _log(List<String> written, {int batch = 30}) => SlowFrameLog(
  write: written.add,
  batch: batch,
  load: () => const ImageCacheLoad(
    images: 312,
    bytes: 98000000,
    live: 120,
  ),
);

/// The written lines, decoded — the format is a contract with whoever greps it.
List<Map<String, Object?>> _lines(
  List<String> written,
) => <Map<String, Object?>>[
  for (final String line in written)
    jsonDecode(line.substring('tela.frames '.length)) as Map<String, Object?>,
];
