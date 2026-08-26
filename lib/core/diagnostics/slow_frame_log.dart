import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// What Flutter's decode cache held at a moment worth asking about.
///
/// The three numbers that decide whether a wall is thrashing. `ImageCache`
/// evicts by *bytes* against a fixed budget (100MB by default), so a shelf
/// whose decoded thumbnails exceed it does not simply use more memory — it
/// evicts and re-decodes the tiles the user is scrolling back and forth over,
/// which is precisely what "looking up like 3 pages deep it just have poor
/// performance" would look like from the outside.
@immutable
class ImageCacheLoad {
  /// Creates a reading.
  const ImageCacheLoad({
    required this.images,
    required this.bytes,
    required this.live,
  });

  /// Reads the running app's cache.
  factory ImageCacheLoad.now() {
    final ImageCache cache = PaintingBinding.instance.imageCache;
    return ImageCacheLoad(
      images: cache.currentSize,
      bytes: cache.currentSizeBytes,
      live: cache.liveImageCount,
    );
  }

  /// How many decoded images the cache is holding.
  final int images;

  /// How many bytes those decodes occupy. Against `maximumSizeBytes`, this is
  /// the number that says whether eviction is running.
  final int bytes;

  /// How many of them are still referenced by something on screen. A live
  /// count near the total means nothing can be evicted without a re-decode.
  final int live;
}

/// Reports runs of frames that missed their budget, with the decode cache's
/// load at the time.
///
/// **Compiled into release on purpose, and that is the whole point of it.**
/// The only build that reaches the owner's tablet is a release one
/// (`make deploy`), so a `kDebugMode` probe would be stripped out of the only
/// build there is to measure. The cost when nothing is slow is one comparison
/// per frame; nothing is allocated and nothing is written until frames are
/// actually late.
///
/// Rate-limited by construction rather than by a clock: it accumulates and
/// writes one line per [batch] slow frames, so a wall that janks for a minute
/// costs a handful of log lines instead of thousands.
///
/// Read it off the device with:
///
/// ```sh
/// adb logcat -s flutter | grep tela.frames
/// ```
///
/// **[reportWatching] is why that grep is readable.** A probe that only speaks
/// when something is wrong cannot be told apart from a probe that is not
/// running: the first capture off the tablet came back empty, and an empty
/// capture was equally consistent with "no slow frames" and with "the line
/// never reaches logcat". One line at startup settles it before any jank
/// number is believed — `event: watching` and nothing after it means the wall
/// was on time; nothing at all means the log is not arriving and the reading
/// is worthless.
///
/// ```dart
/// final SlowFrameLog frames = SlowFrameLog(write: debugPrint)
///   ..reportWatching();
/// frames.observe(build: timing.buildDuration, raster: timing.rasterDuration);
/// ```
class SlowFrameLog {
  /// Creates a log writing through [write], reading the cache through [load].
  SlowFrameLog({
    required this.write,
    this.load = ImageCacheLoad.now,
    this.budget = defaultBudget,
    this.batch = defaultBatch,
  });

  /// Where a finished batch is written.
  final void Function(String line) write;

  /// How the cache load is read when a batch is written.
  final ImageCacheLoad Function() load;

  /// How long a frame's build or raster may take before it counts as slow.
  ///
  /// Two 60Hz frames. Deliberately well past any refresh rate's own budget:
  /// this is looking for jank a person can see, not for frames that were a
  /// hair late on a 120Hz panel.
  static const Duration defaultBudget = Duration(milliseconds: 32);

  /// How many slow frames make a line.
  static const int defaultBatch = 30;

  /// The budget a frame is measured against.
  final Duration budget;

  /// How many slow frames are gathered before one line is written.
  final int batch;

  int _slow = 0;
  int _worstBuild = 0;
  int _worstRaster = 0;
  int _totalSlow = 0;

  /// Records one frame, writing a line once [batch] slow ones have gathered.
  void observe({required Duration build, required Duration raster}) {
    if (build < budget && raster < budget) return;
    _slow++;
    _totalSlow++;
    _worstBuild = _atLeast(_worstBuild, build);
    _worstRaster = _atLeast(_worstRaster, raster);
    if (_slow < batch) return;
    _flush();
  }

  int _atLeast(int worst, Duration span) =>
      span.inMilliseconds > worst ? span.inMilliseconds : worst;

  /// Writes the one line that proves the probe is running.
  ///
  /// Call it once, at startup. It carries the thresholds it will judge frames
  /// by, so a later batch line can be read against the budget that produced it
  /// rather than against whatever the source says today.
  void reportWatching() =>
      _writeLine(<String, Object>{'event': 'watching', 'batch': batch});

  /// Writes the gathered batch and starts a new one.
  void _flush() {
    _writeLine(<String, Object>{
      'event': 'slow',
      'slow': _slow,
      'slowTotal': _totalSlow,
      'worstBuildMs': _worstBuild,
      'worstRasterMs': _worstRaster,
    });
    _slow = 0;
    _worstBuild = 0;
    _worstRaster = 0;
  }

  /// Writes one line, tagged and carrying the cache load at that moment.
  ///
  /// JSON, per the project's logging rule: these are observability lines, not
  /// something a user reads. They carry no URL, no path and no key — only
  /// counts and milliseconds.
  void _writeLine(Map<String, Object> fields) {
    final ImageCacheLoad cache = load();
    write(
      'tela.frames ${jsonEncode(<String, Object>{
        ...fields,
        'budgetMs': budget.inMilliseconds,
        'imagesCached': cache.images,
        'imageBytes': cache.bytes,
        'imagesLive': cache.live,
      })}',
    );
  }
}
