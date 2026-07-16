import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/providers.dart';

/// Entry point. The [ProviderScope] here is the app's one DI root — every port
/// is bound to an adapter in `app/providers.dart`, never reached for globally.
void main() {
  final ProviderContainer container = ProviderContainer();
  unawaited(_purgeLegacyImageCache(container));
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
