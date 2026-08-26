import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tela/domain/ports/app_visibility.dart';

/// [AppVisibility] over Flutter's own lifecycle binding.
///
/// Listens rather than polls, so a move waiting to delete resumes on the frame
/// the user comes back rather than on a timer's next tick.
///
/// **Deliberately tolerant of a null lifecycle state.** `lifecycleState` is
/// null until the first platform message arrives, and this can be constructed
/// before then; treating unknown as "not foreground" would strand a move that
/// has nothing wrong with it. Unknown reads as foreground and the delete goes
/// on to fail honestly if there turns out to be no screen — the platform's
/// answer is the real gate, and this only avoids paying for it needlessly.
///
/// ```dart
/// final AppVisibility visibility = FlutterAppVisibility();
/// ```
class FlutterAppVisibility implements AppVisibility {
  /// Creates the adapter over the ambient [WidgetsBinding].
  FlutterAppVisibility();

  final List<Completer<void>> _waiting = <Completer<void>>[];
  AppLifecycleListener? _listener;

  @override
  bool get isForeground {
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  Future<void> whenForeground() {
    if (isForeground) return Future<void>.value();
    final Completer<void> waiter = Completer<void>();
    _waiting.add(waiter);
    // Created on first use and kept: an app backgrounded once during a long
    // move is usually backgrounded again, and a listener per wait would leak
    // one binding observer for every file in the batch.
    _listener ??= AppLifecycleListener(onResume: _releaseWaiters);
    return waiter.future;
  }

  void _releaseWaiters() {
    final List<Completer<void>> waiting = List<Completer<void>>.of(_waiting);
    _waiting.clear();
    for (final Completer<void> waiter in waiting) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  /// Drops the binding observer. For a container teardown, and for tests.
  void dispose() {
    _listener?.dispose();
    _listener = null;
    _releaseWaiters();
  }
}
