import 'package:tela/domain/ports/screen_guard.dart';

/// Records every `FLAG_SECURE` change instead of touching a real window.
class FakeScreenGuard implements ScreenGuard {
  /// Every value passed to [setSecure], oldest first.
  final List<bool> requests = <bool>[];

  /// Whether the screen is currently protected.
  bool get isSecure => requests.isNotEmpty && requests.last;

  @override
  Future<void> setSecure({required bool secure}) async {
    requests.add(secure);
  }
}
