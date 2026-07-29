import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/download_queue_notice.dart';
import 'package:tela/app/providers.dart';

/// Entry point. The [ProviderScope] here is the app's one DI root — every port
/// is bound to an adapter in `app/providers.dart`, never reached for globally.
///
/// The database is the one binding *applied* here rather than defaulted there.
/// [telaDatabaseProvider] deliberately has no default, so a test that forgets
/// to fake a Drift-backed port fails by name instead of quietly opening the
/// real thing. [openTelaDatabase] is still the adapter, and still lives beside
/// every other one; this is only the line that switches it on for the app.
void main() {
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
