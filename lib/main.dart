import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/download_queue_notice.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/diagnostics/slow_frame_log.dart';

/// Entry point. The [ProviderScope] here is the app's one DI root — every port
/// is bound to an adapter in `app/providers.dart`, never reached for globally.
///
/// The database is the one binding *applied* here rather than defaulted there.
/// [telaDatabaseProvider] deliberately has no default, so a test that forgets
/// to fake a Drift-backed port fails by name instead of quietly opening the
/// real thing. [openTelaDatabase] is still the adapter, and still lives beside
/// every other one; this is only the line that switches it on for the app.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _watchFrameTimes();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[telaDatabaseProvider.overrideWith(openTelaDatabase)],
  );
  unawaited(_purgeLegacyImageCache(container));
  // On the container, above [runApp], because the queue outlives the screen:
  // the engine is cached natively, so a batch keeps draining after the
  // activity is gone — and with it, every frame. Starting the anchor also
  // starts the queue controller, which demotes whatever a killed process left
  // mid-flight; a queue that only woke when its own tab was opened would leave
  // a batch the user closed the app on waiting to be found.
  anchorOwedDownloads(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const TelaApp()),
  );
}

/// Starts the frame probe that answers "why is the wall slow three pages in".
///
/// Wired here rather than inside a screen because it measures the *engine*, not
/// a widget: it wants every frame the process draws, whichever shelf drew it.
/// It is in release builds deliberately — see [SlowFrameLog] for why a
/// debug-only probe would measure the one build nobody runs on the device — and
/// costs one comparison per frame while nothing is late.
///
/// It announces itself before the first frame, so that a capture with nothing
/// in it is a broken log rather than a quiet one. Start `adb logcat` *before*
/// launching, or read the buffer back with `adb logcat -d`: the watching line
/// is written in the first moments of the process and is not repeated.
void _watchFrameTimes() {
  final SlowFrameLog frames = SlowFrameLog(write: debugPrint)..reportWatching();
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final FrameTiming timing in timings) {
      frames.observe(
        build: timing.buildDuration,
        raster: timing.rasterDuration,
      );
    }
  });
}

/// Gives back what an older tela cached, without making anyone ask for it.
///
/// Unawaited, and deliberately: it is disk housekeeping, not a first frame, and
/// nothing on screen depends on it. Failure is silent for the same reason —
/// the worst case is the disk the user already had.
///
/// It is here rather than behind the Settings tile because the abandoned bucket
/// never shrinks on its own (see `legacyImageCacheKey`), so leaving it to be
/// found is leaving it forever on every device that does not go looking.
Future<void> _purgeLegacyImageCache(ProviderContainer container) async {
  try {
    await container.read(fetchedImageCacheProvider).purgeLegacyCache();
  } on Object {
    // Nothing to tell the user: they never knew this cache existed.
  }
}
