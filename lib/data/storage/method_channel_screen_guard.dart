import 'package:flutter/services.dart';
import 'package:tela/domain/ports/screen_guard.dart';

/// Signature of tela's native screen-protection method.
typedef InvokeScreenGuardMethod =
    Future<void> Function(String method, Map<String, bool> arguments);

/// [ScreenGuard] backed by Android's `FLAG_SECURE` on the app window.
///
/// The flag is a property of the *window*, not of a route, so it is turned on
/// when the private library opens and off when it closes. Leaving it on would
/// silently block screenshots of the whole app; never turning it on would leave
/// an explicit wallpaper sitting in the app-switcher thumbnail.
///
/// It **reference-counts** its holders. The grid and the fullscreen viewer are
/// two routes stacked on the same window, and each pairs one acquire with one
/// release; a bare `clearFlags` on the viewer's way out would strip protection
/// from the grid still sitting behind it. Counting means the window turns
/// secure on the first acquire and clears only after the last release — so the
/// flag survives the whole private flow, viewer and sheets included.
class MethodChannelScreenGuard implements ScreenGuard {
  /// Creates an adapter whose native invocation can be replaced in tests.
  MethodChannelScreenGuard({InvokeScreenGuardMethod? invokeMethod})
    : _invokeMethod = invokeMethod ?? _invokeNativeMethod;

  final InvokeScreenGuardMethod _invokeMethod;

  /// How many screens currently want the window protected.
  int _holds = 0;

  static const MethodChannel _channel = MethodChannel('cc.pym.tela/screen');

  @override
  Future<void> setSecure({required bool secure}) async {
    final bool wasSecure = _holds > 0;
    _holds = secure ? _holds + 1 : (_holds > 0 ? _holds - 1 : 0);
    final bool nowSecure = _holds > 0;
    // Only the window's actual edges cross the channel: a second holder while
    // already secure, or a release that still leaves one, changes nothing.
    if (wasSecure == nowSecure) return;
    await _invokeMethod('setSecure', <String, bool>{'secure': nowSecure});
  }

  static Future<void> _invokeNativeMethod(
    String method,
    Map<String, bool> arguments,
  ) {
    return _channel.invokeMethod<void>(method, arguments);
  }
}
