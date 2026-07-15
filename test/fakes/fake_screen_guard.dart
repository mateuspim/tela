import 'package:tela/domain/ports/screen_guard.dart';

/// Records every `FLAG_SECURE` change instead of touching a real window.
///
/// Models the adapter's reference counting: the window is protected while more
/// acquires than releases have landed, so a viewer releasing on its way out
/// still leaves the grid behind it secure. [isSecure] folds the balance rather
/// than reading the last value.
class FakeScreenGuard implements ScreenGuard {
  /// Every value passed to [setSecure], oldest first.
  final List<bool> requests = <bool>[];

  /// Whether the screen is currently protected — more acquires than releases.
  bool get isSecure =>
      requests.fold<int>(
        0,
        (int held, bool secure) =>
            secure ? held + 1 : (held > 0 ? held - 1 : 0),
      ) >
      0;

  @override
  Future<void> setSecure({required bool secure}) async {
    requests.add(secure);
  }
}
