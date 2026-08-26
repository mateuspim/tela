import 'dart:async';

import 'package:tela/domain/ports/app_visibility.dart';

/// In-memory [AppVisibility] a test can put in the background and bring back.
///
/// Foreground by default, which is the state every test that is not about
/// backgrounding wants — and the one the real adapter falls back to when the
/// binding has not reported a lifecycle yet.
class FakeAppVisibility implements AppVisibility {
  /// Creates a fake that starts foreground unless told otherwise.
  FakeAppVisibility({bool foreground = true}) : _foreground = foreground;

  bool _foreground;
  final List<Completer<void>> _waiting = <Completer<void>>[];

  /// How many callers are parked in [whenForeground] right now.
  ///
  /// Records the *shape* of the wait, not just its effect: the point of the
  /// gate is that a background move genuinely stops before the delete, and a
  /// fake that only answered eventually could not tell that from one that
  /// never waited.
  int get waiting => _waiting.length;

  @override
  bool get isForeground => _foreground;

  @override
  Future<void> whenForeground() {
    if (_foreground) return Future<void>.value();
    final Completer<void> waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  /// Sends the app to the background. Anything asked from now on waits.
  void background() => _foreground = false;

  /// Brings it back and releases everything parked.
  void foreground() {
    _foreground = true;
    final List<Completer<void>> waiting = List<Completer<void>>.of(_waiting);
    _waiting.clear();
    for (final Completer<void> waiter in waiting) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}
